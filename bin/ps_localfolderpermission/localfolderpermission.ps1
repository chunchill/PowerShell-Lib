
#Value	Meaning
#0 				Disk Drive
#1 				Print Queue
#2 				Device
#3				IPC
#2147483648 	Disk Drive Admin
#2147483649 	Print Queue Admin
#2147483650 	Device Admin
#2147483651 	IPC Admin

#folder permission 
#1179817 			Read
#1180063            Read,Write
#1179817            ReadAndExecute
#-1610612736        ReadAndExecuteExtended
#1245631 			ReadAndExecute,Modify,Write
#1180095 			ReadAndExecute,Write
#268435456          FullControl(Sub Only)
#1245631 			Change
#2032127 			FullControl
param([string]$logpath,[string]$configpath)

$LocalFolderPermissionMap=@{"modify"			=[System.Security.AccessControl.FileSystemRights]::Modify;
							"Read"				=[System.Security.AccessControl.FileSystemRights]::Read;
							"Write"				=[System.Security.AccessControl.FileSystemRights]::Write;
							"FullControl"		=[System.Security.AccessControl.FileSystemRights]::FullControl;
							"ListDirectory"		=[System.Security.AccessControl.FileSystemRights]::ListDirectory;
							"ReadAndExecute"	=[System.Security.AccessControl.FileSystemRights]::ReadAndExecute;}

trap{
	$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
	writeLogfile -context $message
	Write-Host $message -ForegroundColor Red 
	continue
}

#write log
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","LOCALFOLDER PERMISSION",(Get-Date),$context) 
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII  -ErrorAction Stop 
	}
}

function SetLocalFolderAccess {
param([string]$Path,[string]$Permission,[string]$User)
process{
	if (Test-Path -Path $Path -PathType Container) {
		## Get the current ACL.
		$acl = Get-Acl -Path $Path 

		## Setup the access rule.
		$allInherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit", "ObjectInherit"
		$allPropagation = [System.Security.AccessControl.PropagationFlags]"None"
		$AR = New-Object System.Security.AccessControl.FileSystemAccessRule($User, $Permission, $allInherit, $allPropagation, "Allow")

		## Check if Access already exists.
		if ($acl.Access | Where { $_.IdentityReference -eq $User}) {
			$accessModification = New-Object System.Security.AccessControl.AccessControlModification
			$accessModification.value__ = 2
			$modification = $false
			$acl.ModifyAccessRule($accessModification, $AR, [ref]$modification) | Out-Null
		} else {
			$acl.AddAccessRule($AR)
			
		}
		Set-Acl -AclObject $acl -Path $Path
		Return $true
		} 
		else {
			Return $false
		}
	}		
}

$localfolders=([xml](Get-Content $configpath)).platformdeployment.localfolderconfig.localfolder
$localfolders | ForEach-Object{

	$servers=$_.svrnames.split(",")
	$Path=$_.path
	$sharename=$_.sharename
	$addAccounts=$_.addaccount	
	$addAccounts | ForEach-Object {
	    $User=$_.name
		$Permission=$_.permission
		$servers |foreach-object {
		    if($Env:COMPUTERNAME -eq $_){
				$localpath=$Path
			}
			else{
				$localpath="\\$_\"+$Path.replace(":","$")
			}
			Write-Host "================================="
			Write-Host "Set folder permission on $_"
			Write-Host "================================="
			$result=SetLocalFolderAccess -Path $localpath -Permission $Permission -User $User
			if($result){
				$message=[string]::Format("{0} {1}","[INFO]","set user $User : $Permission permission  on $localpath is successful")
				writeLogfile -context $message
				Write-Host $message 
			}
			else{
			    $message=[string]::Format("{0} {1}","[ERROR]","set user $User : $Permission permission  on $localpath is failed")
				writeLogfile -context $message
				Write-Host $message  -ForegroundColor red
			}
			Write-Host ""
		}
	}
}

