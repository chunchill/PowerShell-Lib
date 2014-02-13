#current envirnoment info
param([string]$configpath,[string]$logpath,[string]$taskname)

$global:svcStatusReport=@()
$global:svcModeReport=@()
$global:svcLogonReport=@()

$svcStatusTitlsDic=@{"ServerName"="";"ServiceName"="";"CurrentStatus"="";"ExecuteResult"=""}
$svcModeTitlsDic=@{"ServerName"="";"ServiceName"="";"CurrentMode"="";"ExecuteResult"=""}
$svcLogonTitlsDic=@{"ServerName"="";"ServiceName"="";"CurrentLogonUser"="";"ExecuteResult"=""}
	
trap{
	    $errmsg="[ERROR]"+$_.exception.message
		writeLogfile -context $errmsg ;
	    Write-Host -ForegroundColor Red $errmsg
		continue;
}

function AddItemToReport($reportItemDic,$flag){
	$objReportItem=New-Object system.Object 
	$reportItemDic.keys | ForEach-Object{
		$objReportItem | Add-Member -MemberType NoteProperty -Name $_ -Value ($reportItemDic[$_])
	}
	switch($flag){
		"status"{$global:svcStatusReport+=$objReportItem;break}
		"mode"{$global:svcModeReport+=$objReportItem;break}
		"logon"{$global:svcLogonReport+=$objReportItem;break}
	}
}

#define the error message
function getexecresult ([int]$returnCode) { 
    if($returnCode -ne $null)
    {
        switch ($returnCode) { 
			0 {$execmessage="Successful"; break}
            1 {$execmessage="Not Supported"; break} 
            2 {$execmessage="Access Denied"; break} 
            3 {$execmessage="Dependent Services Running"; break} 
            4 {$execmessage="Invalid Service Control"; break} 
            5 {$execmessage="Service Cannot Accept Control"; break} 
            6 {$execmessage="Service Not Active"; break} 
            7 {$execmessage="Service Request Timeout"; break} 
            8 {$execmessage="Unknown Failure"; break} 
            9 {$execmessage="Path Not Found"; break} 
            10 {$execmessage="Service Already Running"; break} 
            11 {$execmessage="Service Database Locked"; break} 
            12 {$execmessage="Service Dependency Deleted"; break} 
            13 {$execmessage="Service Dependency Failure"; break} 
            14 {$execmessage="Service Disabled"; break} 
            15 {$execmessage="Service Logon Failure"; break} 
            16 {$execmessage="Service Marked For Deletion"; break} 
            17 {$execmessage="Service No Thread"; break} 
            18 {$execmessage="Status Circular Dependency"; break} 
            19 {$execmessage="Status Duplicate Name"; break} 
            20 {$execmessage="Status Invalid Name"; break} 
            21 {$execmessage="Status Invalid Parameter"; break} 
            22 {$execmessage="Status Invalid Service Account"; break} 
            23 {$execmessage="Status Service Exists"; break} 
            24 {$execmessage="Service Already Paused"; break} 
        } 
    }
    else
    {
        Write-Host -ForegroundColor Red "The input parameter returnCode cannot be null"
        $execmessage="The input parameter returnCode cannot be null"
    }
    return $execmessage
} 

#write log
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","WINDOW SERVICES",(Get-Date),$context) 
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII  -ErrorAction Stop 
	}
}

function windowsserviceoperation($taskname) {
	process{
		    ([xml](get-content $configpath)).platformdeployment.windowsservice.server |where{$_.taskname -eq $taskname} | ForEach-Object{
			trap{
				$errmsg="[ERROE]"+$_.exception.message
				writeLogfile -context $errmsg ;
				Write-Host -ForegroundColor Red $errmsg
				continue;
			}
			$servernames=$_.name.split(",")
			$servicename=$_.service.name
			$action=@{}
			$_.service.actions |foreach-object{
				
				if($_.resetstatus){
					$action.add("status",$_.resetstatus.status)
				}
				if($_.resetmode){
					$action.add("mode",$_.resetmode.mode)
				}
				if($_.resetlogon){
					$action.add("resetlogon",@($_.resetlogon.account,$_.resetlogon.password))
				}
			}
			processervicerequest -servernames $servernames -servicename $servicename -action $action
		}
	}
}

function processervicerequest{
	param($servernames, `
		  $servicename, `
		  $action)
	process{
		$servernames |ForEach-Object{
			trap{
				$errmsg="[ERROE]"+$_.exception.message
				writeLogfile -context $errmsg ;
				Write-Host -ForegroundColor Red $errmsg
				continue;
			}
		    $servername=$_
			$status=$null
			
			if($action.containskey("status")){
				$status=$action["status"]
			}
			
			$currentsvc=Get-WmiObject -Class win32_service -filter "name='$servicename'" -ComputerName $servername
			
			if($status -and ($currentsvc -ne $null)){
				Get-Service -DependentServices -Name $servicename -ComputerName $servername | select name | ForEach-Object{
					$dependencyname=$_.name
					$dependencysvc=Get-WmiObject -Class win32_service -filter "name='$dependencyname'" -ComputerName $servername
					if($dependencysvc -ne $null){
						serviceoperation -status $status -svcInstance $dependencysvc -svcname $dependencyname -servername $servername
					}
				}
				serviceoperation -status $status -svcInstance $currentsvc -svcname $servicename -servername $servername
			}
			
			if($currentsvc -ne $null){
				$mode=$null
				$resetlogon=$null
				if($action.ContainsKey("mode")){
			    	$mode=$action["mode"]
				}
				if($action.ContainsKey("resetlogon")){
					$resetlogon=$action["resetlogon"]
				}
				if($mode){
				    $message="====Change $servicename Mode on $serverName=====`n"
					$retuncode=$currentsvc.changestartmode($mode)
					$execResult=getexecresult -returnCode $retuncode.ReturnValue
					$message+="Change $servicename mode:$execResult"
					writeLogfile -context $message 
					
					$svcModeTitlsDic["ServerName"]=$serverName
					$svcModeTitlsDic["ServiceName"]=$servicename
					$svcModeTitlsDic["CurrentMode"]=$currentsvc.StartMode
					$svcModeTitlsDic["ExecuteResult"]=$execResult
					AddItemToReport -flag "mode" -reportItemDic $svcModeTitlsDic
				}
				if($resetlogon){
					$message="====Change $servicename logon on $serverName=====`n"
	
				    $account=$resetlogon[0]
					$password=$resetlogon[1]
					$currentsvc.StopService() |out-null
					$retuncode=$currentsvc.change($null,$null,$null,$null,$null,$null,$account,$password,$null,$null,$null) 
					$execResult=getexecresult -returnCode $retuncode.ReturnValue
					$message+="Change $servicename logon:$execResult; account=$account"
					writeLogfile -context $message
					
					$svcLogonTitlsDic["ServerName"]=$serverName
					$svcLogonTitlsDic["ServiceName"]=$servicename
					$svcLogonTitlsDic["CurrentLogonUser"]=$currentsvc.logonuser
					$svcLogonTitlsDic["ExecuteResult"]=$execResult
					AddItemToReport -flag "logon" -reportItemDic $svcModeTitlsDic
					
					$currentsvc.StartService() |out-null
				}
			}
		}
	}
}

function getServiceState($servicename,$servername){
	$currentsvc=Get-WmiObject -Class win32_service -filter "name='$servicename'" -ComputerName $servername
	return $currentsvc.state
}

function serviceoperation{
	param($status,$svcname,$svcInstance,$servername)
	process{
		if($svcInstance.startmode -eq "disabled"){
			$svcInstance.changestartmode("automatic")  |out-null
		}
		
		$execResult=''
		switch($status){
			"start" {
				$message="====Start Services $svcname on $serverName=====`n"
	            switch ($svcInstance.state){
					"paused" {
						$retuncode=$svcInstance.ResumeService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="ResumeService $svcname : $execResult.`n"
						writelogfile -context $message
						break
					}
					"running"{$execResult="Already Running";break}
					"stopped"{
						#$retuncode=$svcInstance.StartService()
						$retuncode=$svcInstance.InvokeMethod("StartService",$null, $null)
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="StartService $svcname : $execResult.`n"
						writelogfile -context $message
						break	
					}
				}
				break
			}
			"stop" {
				 $message="====Stop Services $svcname on $serverName=====`n"
			     switch ($svcInstance.state){
					"paused" {
						$retuncode=$svcInstance.ResumeService()
				
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="ResumeService $svcname : $execResult.`n"
						writelogfile -context $message
					
						
						$retuncode=$svcInstance.StopService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="StopService $svcname : $execResult.`n"
						writelogfile -context $message
						
						break
					}
					"running"{
						$retuncode=$svcInstance.StopService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="StopService $svcname : $execResult.`n"
						writelogfile -context $message
						
						break
					}
					"stopped"{$execResult="Already Stopped";break}
				}
				break
			}
			"pause" {
				$message="====Pause Services $svcname on $serverName=====`n"
				switch ($svcInstance.state){
					"paused" {$execResult="Already Pause";break}
					"running"{
						$retuncode=$svcInstance.PauseService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="PauseService $svcname : $execResult.`n"
						writelogfile -context $message
					
						break
					}
					"stopped"{
						$retuncode=$svcInstance.StartService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="StartService $svcname:$execResult.`n"
						writelogfile -context $message
					
						$retuncode=$svcInstance.PauseService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="PauseService $svcname : $execResult.`n"
						writelogfile -context $message
					
						break
					}
				}
				break
			}
			"resume" {
				$message="====Resume Services $svcname on $serverName=====`n"
				switch ($svcInstance.state){
					"paused" {
						$retuncode=$svcInstance.ResumeService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="ResumeService $svcname : $execResult.`n"
						writelogfile -context $message
						
						break
					}
					"running"{
						$execResult="Already Resume";break
					}
					"stopped"{
						$retuncode=$svcInstance.StartService()
						$execResult=getexecresult -returnCode $retuncode.ReturnValue
						$message+="StartService $svcname : $execResult.`n"
						writelogfile -context $message
						
       					break
					}
				}
				break
			}
		}
		$svcStatusTitlsDic["ServerName"]=$servername
		$svcStatusTitlsDic["ServiceName"]=$svcname
		$svcStatusTitlsDic["CurrentStatus"]=(Get-Service -ComputerName $servername  -Name $svcname).status
		$svcStatusTitlsDic["ExecuteResult"]=$execResult
		AddItemToReport -flag "status" -reportItemDic $svcStatusTitlsDic
	}
}

"The WINDOWS SERVICE operational script is running,please wait a moment till it is completed."
$startTime=Get-Date

windowsserviceoperation -taskname $taskname

$global:svcStatusReport | ft -Property ServiceName,ServerName,CurrentStatus,ExecuteResult -AutoSize
$global:svcModeReport| ft -Property ServiceName,ServerName,CurrentMode,ExecuteResult -AutoSize
$global:svcLogonReport| ft -Property ServiceName,ServerName,CurrentLogonUser,ExecuteResult -AutoSize

$endTime=Get-Date
$elapsedtime=(New-TimeSpan $startTime $endTime ).TotalSeconds
write-host "Elapsed time : $elapsedtime s"  -ForegroundColor Yellow 
