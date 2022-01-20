<#
.SYNOPSIS
This script migrate from UPM to FSLogix Profile Container

.DESCRIPTION
Test before using!!

.NOTES
  Version:          1.3
  Author:           
  Rewrite Author:   Manuel Winkel <www.deyda.net>
  Creation Date:    2020-03-04
  Purpose/Change:
  2022-01-20      Add variable to change the Profile Container folder
#>
#########################################################################################
# Setup Parameter first here newprofile oldprofile subfolder1 subfolder2
# Requires -RunAsAdministrator
# My Userprofiles come only with SAMAccount Name without Domain "\Username\2012R2\UPM_Profile
#########################################################################################
# Example from my UPM Path "c:\share\username\2012R2\UPM_Profile"
# Example for Profile Container Name "emea"+"\"+$sam+"."+$Domain

# fslogix Root profile path
$newprofilepath = "c:\share\xdprofile"
# UPM Root profile path
$oldprofilepath = "c:\share\fslogix"
# Subfolder 1 - First Path to UPM_Profile Folder in UPM Profiles - see my example above
$subfolder1 = "Win2019"
# Subfolder 2 - First Path to UPM_Profile Folder in UPM Profiles - see my example above
$subfolder2 = "UPM_Profile"
# Username - If it is not a SamAccountname the domain must be defined here (Leave blank for SamAccountName)
$Domain = "deyda.net"

#########################################################################################
$oldprofiles = Get-ChildItem $oldprofilepath | Select-Object -Expand fullname | Sort-Object | out-gridview -OutputMode Multiple -title "Select profile(s) to convert"| ForEach-Object{
Join-Path $_ $subfolder1\$subfolder2
}
#$old = $oldprofiles
foreach ($old in $oldprofiles) {
$sam = Split-Path ($old -split $subfolder1)[0] -leaf
If ($Domain) {
  $sam = Split-Path ($sam -split "."+$domain)[0] -leaf
}
$sid = (New-Object System.Security.Principal.NTAccount($sam)).translate([System.Security.Principal.SecurityIdentifier]).Value
# fslogix profile folder name (Please use the variable $sid for the SID and $sam for the username)
$newprofilefolder = "emea"+"\"+$sam+"."+$Domain
$regtext = "Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid]
`"ProfileImagePath`"=`"C:\\Users\\$sam`"
`"FSL_OriginalProfileImagePath`"=`"C:\\Users\\$sam`"
`"Flags`"=dword:00000000
`"State`"=dword:00000000
`"ProfileLoadTimeLow`"=dword:00000000
`"ProfileLoadTimeHigh`"=dword:00000000
`"RefCount`"=dword:00000000
`"RunLogonScriptSync`"=dword:00000000
"

$nfolder = join-path $newprofilepath ($newprofilefolder)
if (!(test-path $nfolder)) {New-Item -Path $nfolder -ItemType directory | Out-Null}
& icacls $nfolder /setowner "$env:userdomain\"+"$sam" /T /C
& icacls $nfolder /grant $env:userdomain\"+"$sam`:`(OI`)`(CI`)F /T
$vhd = Join-Path $nfolder ("Profile_"+$sam+".vhdx")

$script1 = "create vdisk file=`"$vhd`" maximum 30720 type=expandable"
$script2 = "sel vdisk file=`"$vhd`"`r`nattach vdisk"
$script3 = "sel vdisk file=`"$vhd`"`r`ncreate part prim`r`nselect part 1`r`nformat fs=ntfs quick"
$script4 = "sel vdisk file=`"$vhd`"`r`nsel part 1`r`nassign letter=T"
$script5 = "sel vdisk file`"$vhd`"`r`ndetach vdisk"
#$script6 = "sel vdisk file=`"$vhd`"`r`nattach vdisk readonly`"`r`ncompact vdisk"

if (!(test-path $vhd)) {
$script1 | diskpart
$script2 | diskpart
Start-Sleep -s 5
$script3 | diskpart
$script4 | diskpart
& label T: Profile-$sam
New-Item -Path T:\Profile -ItemType directory | Out-Null

start-process icacls "T:\Profile /setowner SYSTEM"
Start-Process icacls -ArgumentList "T:\Profile /inheritance:r"
$cmd1 = "T:\Profile /grant $env:userdomain\$sam`:`(OI`)`(CI`)F"
Start-Process icacls -ArgumentList "T:\Profile /grant SYSTEM`:`(OI`)`(CI`)F"
Start-Process icacls -ArgumentList "T:\Profile /grant Administrators`:`(OI`)`(CI`)F"
Start-Process icacls -ArgumentList $cmd1
} else {

$script2 | diskpart
Start-Sleep -s 5
$script4 | diskpart
}

"Copying $old to $vhd"
& robocopy $old T:\Profile /E /Purge /r:0 | Out-Null

if (!(Test-Path "T:\Profile\AppData\Local\FSLogix")) {
New-Item -Path "T:\Profile\AppData\Local\FSLogix" -ItemType directory | Out-Null
}

if (!(Test-Path "T:\Profile\AppData\Local\FSLogix\ProfileData.reg")) {$regtext | Out-File "T:\Profile\AppData\Local\FSLogix\ProfileData.reg" -Encoding ascii}
$script5 | diskpart
}
