
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

$FileShareMap=@{"Read"							=1179817;
				"Read,Write"					=1180063;
				"ReadAndExecute"				=1179817;
				"ReadAndExecuteExtended"		=-1610612736;
				"ReadAndExecute,Modify,Write"	=1245631;
				"ReadAndExecute,Write"			=1180095;
				"FullControl(Sub Only)"			=268435456;
				"Change"						=1245631;
				"FullControl"					=2032127}
				
				
$ShareReturnResult=@{0="Success";
					2="Access Denied";
					8="Unknown Failure";
					9="Invalid Name";
					10="Invalid Level";
					21="Invalid Parameter";
					22="Duplicate Share";
					23="Redirected Path";
					24="Unknown Device or Directory";
					25="Net Name Not Found"}
					
$SetSDResult=@{
					0='Success';
					2='Access Denied';
					8='Unknown Failure';
					9='Privilege Missing';
					21='Invalid Parameter'}

trap{
	$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
	writeLogfile -context $message
	Write-Host $message -ForegroundColor Red 
	continue
}

function SetLocalFolderAccess {
	param (
		[String]$Path,
		[String]$User,
		[String]$Permission
	)
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
	} else {
		Return $false
	}
}

#write log
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","SHAREFOLDER PERMISSION",(Get-Date),$context) 
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII  -ErrorAction Stop 
	}
}
function setShareFolderAccess{
	process{
		$shareFolders=([xml](Get-Content $configpath)).platformdeployment.sharefolderconfig.sharefolder
		
		$shareFolders |ForEach-Object {
			$servers=$_.svrnames.split(",")
			$Path=$_.path
			$sharename=$_.sharename
			
			$addAccounts=$_.addaccount
			$rmvAccounts=$_.removeaccount
			
			$servers | ForEach-Object {
			    $servername=$_
				$SS=getSecuritySetting -strComputer $servername -strShareName $sharename
				if($SS -eq $null){	
					$Shares=[WMICLASS] "\\$servername\ROOT\CIMV2:WIN32_Share"
					$result=$Shares.Create($Path,$sharename,0,$null,$null,$null,([wmiclass]"Win32_SecurityDescriptor").createinstance()).ReturnValue
					if($result -eq 0){

						$message="Share the folder $sharename : $Path successfully."
						writelogfile -context $message
						Write-Host $message -ForegroundColor Yellow
					}
					else{
						$message="[INFO] $($ShareReturnResult[[int]$result]) when share the folder($Path) on $servername."
						Write-Host $message -ForegroundColor Red
						writeLogfile $message
					}
					
					$SS=getSecuritySetting -strComputer $servername -strShareName $sharename
					if($SS -eq $null){
						throw "Failure about share the folder($sharename) on $servername.please check folder path is corrent."
					}
				}
				
				$message="=================================`r`n"
				$message+="Begin add sharefoler($sharename) permission on $servername `r`n"
				$message+="================================="
				Write-Host $message  
				writeLogfile $message
				
				$objSDRequest=getSDRequestByXml -addAccountNodes $addAccounts -rmvAccountNodes $rmvAccounts
				$SD=getSecurityDescriptor -SDRequest $objSDRequest -SS $SS
				$result=($SS.SetSecurityDescriptor($SD)).returnvalue
				if($result -eq 0){
				  	Write-Host "Set sharefolder permission successfully." -ForegroundColor Yellow 
				}
				else{
				    $message="[INFO] $($SetSDResult[[int]$result]) when set sharefolder($Path) permission on $servername."
					Write-Host $message -ForegroundColor Red
					writeLogfile $message
				}
				Write-Host ""
			}
		}
	}
}

function getSDRequestByXml{
	param(	$addAccountNodes, `
			$rmvAccountNodes)
	process{
		$objSDRequest=New-Object system.Object 
		$objSDRequest |	Add-Member -MemberType NoteProperty  -Name addAccountDic -Value $null
		$objSDRequest |	Add-Member -MemberType NoteProperty  -Name rmvAccountList -Value $null
		
		$addAccountDic=@{}
		$rmvAccountList=@()
		
		$addAccountNodes |ForEach-Object {
			if(!$addAccountDic.contains($_.name)){
				$addAccountDic.add($_.name,$_.permission)
			}
		}
		$rmvAccountNodes | ForEach-Object {
			$rmvAccountList+= $_.name
		}
		$objSDRequest.addAccountDic=$addAccountDic
		$objSDRequest.rmvAccountList=$rmvAccountList
		return $objSDRequest
	}
}

function getSecuritySetting{
	param(	[string]$strComputer,`
			[string]$strShareName)
	process{
		$objSecuritySettings=get-wmiobject -Namespace  root\cimv2 `
						-ComputerName $strComputer `
						-Class Win32_LogicalShareSecuritySetting `
						-Filter "name='$strShareName'"
		return $objSecuritySettings
	}
}

function getSecurityDescriptor{
	param(	[system.Object]$SDRequest,`
			$SS)
			
	process{
		if($SS -eq $null){
			$SD=([wmiclass]"Win32_SecurityDescriptor").createinstance()
		}
		else{
			$SD=$SS.GetSecurityDescriptor().Descriptor
		}
		
		$addAccountList=@()
		$rmvAccountList=@()
		if($SDRequest -ne $null){
			$addAccountDic=$SDRequest.addAccountDic
			$rmvAccountList=$SDRequest.rmvAccountList
		}
		#add ACEs
		$addACEs=@()
		$addAccountDic.keys | ForEach-Object {
			$strUser=$_
			if($_.contains('\')){
				$arrayAccount=$_.split('\')
				$strDomainName=$arrayAccount[0]
				$strUserName=$arrayAccount[1]
			}
			else{
				$strDomainName=$null
				$strUserName=$strUser
			}
			
			$objTrustee = ([wmiclass]"Win32_Trustee" ).createinstance()

			$SID = (new-object security.principal.ntaccount $strUser).translate([security.principal.securityidentifier]) 
			$objTrustee.SIDString = "S-1-5-11"
			[byte[]] $SIDArray = ,0 * $SID.BinaryLength 
			$SID.GetBinaryForm($SIDArray,0) 

			$objTrustee.SID =$SIDArray
			$objTrustee.SIDLength = $objSID.SIDLength
			$objTrustee.Domain = $strDomainName
			$objTrustee.Name = $strUserName
			
			$sharepermission=$addAccountDic[$_]
			
			if(!$FileShareMap.contains($sharepermission)){
				throw "The account:$strUser 's permission format($($addAccountDic[$_])) is incrrect."
			}
			$objACE =([wmiclass]"Win32_ACE").createinstance()
			$objACE.Trustee = $objTrustee
			$objACE.AccessMask = $FileShareMap[$sharepermission]
			$objACE.AceType = 0
			$objACE.AceFlags = 0
			
			$addACEs+=[System.Management.ManagementBaseObject]$objACE
			
			$message="Add account $strUser :  $sharepermission"
			writelogfile -context $message
			Write-Host $message
		}
	
		#remove ACEs
		$addAccountList=$addAccountDic.keys |ForEach-Object {
		if($_.contains('\')){
				$_.split('\')[1]
			}
			else{
				$_
			}
		}
		$DACL=@()
		$SD.DACL |ForEach-Object{
			$trusteeName=$_.Trustee.Name
			
			$existFlag=$false
			($rmvAccountlist+=$addAccountList) | ForEach-Object {
				if($_ -eq $trusteeName){
					$existFlag=$true
				}
			}
			if(!$existFlag){
				$DACL+=[System.Management.ManagementBaseObject]$_
			}
		}
		$SD.DACL=$DACL
		$SD.DACL+=$addACEs
		return $SD
	}
}
setShareFolderAccess