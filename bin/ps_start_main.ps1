#ps_start_main
$curPath=$MyInvocation.MyCommand.Definition
$curScriptName=$MyInvocation.MyCommand.Name
$curDictory=[string]$curPath.replace($curScriptName,"")
$logDictory=Join-Path $curDictory "log"

$date=Get-Date
$logfilename=[String]::Format("{0}_{1}_{2}.txt",$date.Year,$date.Month,$date.Day)

$logpath= Join-Path $logDictory $logfilename
$configpath= Join-Path $curDictory "config.xml"

#write log
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","PLATFORM DEPLOYMENT",(Get-Date),$context)  
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII  -ErrorAction Stop 
	}
}
function writeLogBegin{
	writeLogfile -context "##############################BEGIN LOGGING#######################################"
}
function writeLogEnd{
	writeLogfile -context "##############################END LOGGING#########################################"
}
writeLogBegin

#copyfile
write-host "[process  1]copy file"
$copyscriptpath=Join-Path  $curDictory "\ps_copyfile\copyfile.ps1"
& "$copyscriptpath"		-copygroupname "install_certificate" `
						-logpath $logpath `
						-configpath $configpath
					
#remote execution
write-host "[process  2]remote execution"
$remotescriptpath=Join-Path  $curDictory "\ps_remote_execution\RemoteProcess.ps1"
& "$remotescriptpath"	-logpath $logpath -configpath $configpath

#set sharefolder permission
#write-host "[process  6]set sharefolder permission"
#$sfscriptpath=Join-Path  $curDictory "\ps_sharefolderpermission\sharefolderpermission.ps1"
#& "$sfscriptpath" -configpath $configpath  -logpath $logpath 

#set localfolder permission
#write-host "[process  6]set localfolder permission"
#$lfscriptpath=Join-Path  $curDictory "\ps_localfolderpermission\localfolderpermission.ps1"
#& "$lfscriptpath" -configpath $configpath  -logpath $logpath 

######################################################################################						
$message= new-object system.Text.StringBuilder
$null=$message.appendline("----------------------------------------------")
$null=$message.appendline("Copyright (c)2012")
$null=$message.appendline("Author    Zeno(zheng.peng@hp.com)")
$null=$message.appendline("Log       $logpath.")

Write-Host $message -ForegroundColor  Green
writeLogEnd


