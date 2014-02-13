#remote start
param ([string]$logpath,[string]$configpath)
#trap exception
trap{
	$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
	writeLogfile -context $message
	Write-Host $message -ForegroundColor Red 
	continue
}

function initEvironment{
	if(!(Test-Path $logDictory)){
		New-Item -Path $curDictory -Name "log" -ItemType directory -Force |out-null
	}
	
	if(!(Test-Path ($logpath))){
		New-Item -Path $logpath -ItemType file -Force |out-null
	}
}
function remoteExecution{
	param($strCmd,$servers,$pindex)
	begin{}
	process{
	    $index=0
		foreach ($s in $servers)
		{  
			#trap exception
			trap{
				$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
				writeLogfile -context $message
				Write-Host $message -ForegroundColor Red 
				continue
			}
			$index++
			
			$message="$pindex.$index.Begin to execute script{$strCmd} on $s..."
			writeLogfile -context $message
			
			Write-Host "$pindex.$index.Begin to execute script{...\$($strCmd.substring($strCmd.lastindexof("\")+1))} on $s..."
			
			$result = ([WmiClass]"\\$s\ROOT\CIMV2:Win32_Process").create("$strCmd")
			switch ($result.returnvalue){ 
				0 {Write-Host -ForegroundColor Yellow "Successful Completion" ;break} 
				1 {Write-Host -ForegroundColor Red "Not Supported" ; break} 
				2 {Write-Host -ForegroundColor Red "Access Denied"; break} 
				3 {Write-Host -ForegroundColor Red "Dependent Services Running"; break} 
				4 {Write-Host -ForegroundColor Red "Invalid Service Control"; break} 
				5 {Write-Host -ForegroundColor Red "Service Cannot Accept Control"; break} 
				6 {Write-Host -ForegroundColor Red "Service Not Active"; break} 
				7 {Write-Host -ForegroundColor Red "Service Request Timeout"; break} 
				8 {Write-Host -ForegroundColor Red "Unknown Failure"; break} 
				9 {Write-Host -ForegroundColor Red "Path Not Found"; break} 
				10 {Write-Host -ForegroundColor Red "Service Already Running"; break} 
				11 {Write-Host -ForegroundColor Red "Service Database Locked"; break} 
				12 {Write-Host -ForegroundColor Red "Service Dependency Deleted"; break} 
				13 {Write-Host -ForegroundColor Red "Service Dependency Failure"; break} 
				14 {Write-Host -ForegroundColor Red "Service Disabled"; break} 
				15 {Write-Host -ForegroundColor Red "Service Logon Failure"; break} 
				16 {Write-Host -ForegroundColor Red "Service Marked For Deletion"; break} 
				17 {Write-Host -ForegroundColor Red "Service No Thread"; break} 
				18 {Write-Host -ForegroundColor Red "Status Circular Dependency"; break} 
				19 {Write-Host -ForegroundColor Red "Status Duplicate Name"; break} 
				20 {Write-Host -ForegroundColor Red "Status Invalid Name"; break} 
				21 {Write-Host -ForegroundColor Red "Status Invalid Parameter"; break} 
				22 {Write-Host -ForegroundColor Red "Status Invalid Service Account"; break} 
				23 {Write-Host -ForegroundColor Red "Status Service Exists"; break} 
				24 {Write-Host -ForegroundColor Red "Service Already Paused"; break} 
				default {Write-Host -ForegroundColor Red "Have unknow error"; break}
			}
			$message=[string]::Format("server:{0} returnvalue:{1}",$s,$result.returnvalue)
			writeLogfile -context $message
			Write-Host ""
		}
	}
	end{}
}

function remoteExecutionTasks{
	param($config,$logpath)
	process{
		$configobj=[xml](Get-Content $configpath -ErrorAction Stop)
		$pindex=0
		foreach($remotetask in $configobj.platformdeployment.remoteprocess.remotetask){
		    $pindex++
			$remotetask.executepath |ForEach-Object {
				$cmd=$_.execpath
				$servers=$remotetask.servername.svrnames.split(",")
				remoteExecution -strCmd $cmd -servers $servers -pindex  $pindex
			}
		}
	}
}
#logging
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","REMOTE EXECUTION",(Get-Date),$context)  
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII 
	}
}

#begin execution

initEvironment
remoteExecutionTasks -config $configpath -logpath $logpath

