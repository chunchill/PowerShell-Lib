

#current envirnoment info
param([string]$copygroupname,[string]$logpath,[string]$configpath)

$global:xml =$null	
$global:readkey=$null

#Capture gobal exception
trap{
	$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
	writeLogfile -context $message
	Write-Host $message -ForegroundColor Red 
	Write-Host ""
	if($global:xml){
		continue
	}
	else{
		return
	}
}

#create log directory and log file 
function initEvironment{

	if(!(Test-Path $logDictory)){
		New-Item -Path $curDictory -Name "log" -ItemType directory -Force
	}
	
	if(!(Test-Path ($logpath))){
		New-Item -Path $logpath -ItemType file -Force 
	}
}

#get configration file information 
function getConfigInfoDic{
	param([string]$xmlpath)
	begin{
		
		$cofnigDic=@{}
	    if(Test-Path $xmlpath){
			$global:xml=[system.Xml.XmlDocument](Get-Content $xmlpath -ErrorAction Stop)
		}
	}
	process{
		if (!$global:xml){
			#cann't get the configration file
			throw "The configration file is wrong,pls ensure the file type is [xml document]."
		}
		else{
			#we get the configration file dictionary
		    $cofnigDic=getChildNodeDic ($global:xml.platformdeployment.copyfilemission.copygroup | where{$_.groupname -eq $copygroupname})  $cofnigDic
		}
	}
	end{
		return $cofnigDic
	}
}

#recurse config.xml to get the configration dictionary
function getChildNodeDic{
	param($parentNode,$childrenDic)
	begin{}
	process{
		foreach ($childNode in $parentNode.psbase.ChildNodes) {
			if($childNode.psbase.ChildNodes.Count){
			    if(($childNode.enable -eq $null) -or ($childNode.enable -eq "1")){
				    if($childNode.id){
				    	$tempKey=[string]::Format("{0}:{1}",$childNode.psbase.name,$childNode.id)
					}
					else{
						$tempKey=$childNode.psbase.name
					}
				    if(!$childrenDic.Contains($tempKey)){
						$childrenDic.add($tempKey,(getChildNodeDic $childNode @{}))
					}
				}
			}
			else{
			    switch($childNode.psbase.name){
					"sourcesvr" {
					    $key="sourcesvr"
					    if(!$childrenDic.contains($key)){
							$childrenDic.add($key,$childNode.svr.trim())
						}
					}
					"destinationsvr"{
						$key="destinationsvr"
						$value=$childNode.svr
						
					    if(!$childrenDic.contains($key)){
							$childrenDic.add($key,$value.split(","))
						}
					}
					"copyfile"{
					    $key=[string]::Format("{0}#{1}",$childNode.from.trim(),$childNode.to.trim())
						$backuppath=$childNode.backuppath
					    if(!$childrenDic.contains($key)){
							$childrenDic.add($key,[string]::Format("{0}#{1}",$childNode.to.trim(),$backuppath))
						}
					}
					default {
					    $key=[string]::Format("{0}:{1}",$childNode.psbase.name,$childNode.id)
					    if(!$childrenDic.contains($key)){
							$childrenDic.add($key,@{})
						}
					}
				}
			}
		}
	}
	end{
		return $childrenDic
	}
}

function copyFileProcess{
	param($configTaskDic)
	begin{
		if(!$configTaskDic){
			throw "The configration information is null."
		}
	}
	process{
		#task count 
		$taskIndex=0
		#foreach tasks
		foreach ($taskinfo in $configTaskDic.keys){
			#COPY count
			$copyIndex=0
			#write task begin
			$taskIndex++
			$message =[string]::Format("{0}.{1}",$taskIndex,"Begin The Task [$taskinfo].")
			writeLogfile -context $message
			Write-Host $message
			#source info
			$sourcesvr=$configTaskDic[$taskinfo]["sourcesvr"]
			
			#destination info 
			$destinationsvrs=$configTaskDic[$taskinfo]["destinationsvr"]
			$avaliablesvrs= New-Object System.Collections.ArrayList 

			foreach ($svr in $destinationsvrs){
				$svr=transferPath -servername $svr
				$testsvrpath=transferPath -servername $svr -directory  "C:"
				
				if(Test-Path $testsvrpath){
					$null=$avaliablesvrs.add($svr)
				}
				else{
					#the souce directory is wrong.
					$message=[string]::Format("{0} {1}","[ERROR]","The destination server :$svr is wrong.")
					writeLogfile -context $message
					Write-Host $message -ForegroundColor Red 
					Write-Host ""
					continue
				}
			}

			foreach($fromkey in $configTaskDic[$taskinfo]["directorymap"].keys){
			
				$destinationDir=""
				$sourceDir=""
				$backupflg="0"
				
				$sourceDir=$fromkey.remove($fromkey.lastindexof("#"))
				$destStr=$configTaskDic[$taskinfo]["directorymap"][$fromkey].trim()
				
				if($destStr.lastindexof("#")){
				    $tempArray=$destStr.split("#")
					$destinationDir=$tempArray[0]
					$backuppath=$tempArray[1]
				}
				else{
					$destinationDir=$destStr
				}
				
				#execute the copy task
				$sourcePath=transferPath -servername $sourcesvr -directory  $sourceDir
				if(Test-Path $sourcePath){
					foreach($destsvr in $avaliablesvrs){
					    #capture exception
						trap{
							$message=[string]::Format("{0} {1}","[ERROR]",$_.exception.message)
							writeLogfile -context $message
							Write-Host $message -ForegroundColor Red 
							Write-Host ""
							continue
					    }
						#destination directory
						$destPath=transferPath -servername $destsvr -directory  $destinationDir
					    	
						#destination path whether exist
						if(! (Test-Path $destPath)){
						    if(!($global:readkey -eq "a") -and !($global:readkey -eq "na") ){
							    Write-Host "The destination:$destPath is not exist."
						    	$global:readkey=Read-Host "Do you want to create it? (y/n/a/na)"
							}
							if((!($global:readkey -eq "y") -and !($global:readkey -eq "a")) -or ($global:readkey -eq "na")){
								$message="Process is breaked on copying to $destPath."
								writeLogfile -context $message
								Write-Host $message -BackgroundColor Red 
								Write-Host ""
								continue
							}
							New-Item -Path  $destPath -ItemType directory -Force  -ErrorAction Stop
						}
						
						#write begin
						$copyIndex++
						$message =[string]::Format("{0}-{1}.{2}",$taskIndex,$copyIndex,"Begin to Copy Items.")
						writeLogfile -context $message
						Write-Host $message
						
						$message=[string]::Format("From:{0}",$sourcePath)
						writeLogfile -context $message
						Write-Host $message
						
						$message=[string]::Format("To  :{0}",$destPath)
						writeLogfile -context $message
						Write-Host $message
												
						#we will backup file or directory if it need.
						if(($backuppath -ne $null) -and ($backuppath.trim() -ne "")){
							#create it if do not exist backup directory
						    $desbackuppath=transferPath -servername $destsvr -directory  $backuppath
						    if(!(Test-Path $desbackuppath)){
								New-Item -Path  $desbackuppath -ItemType directory -Force  -ErrorAction Stop | Out-Null
								$message=[string]::Format("create backuppath:{0}",$desbackuppath)
						        writeLogfile -context $message
							}
							
							$sourceChild=Split-Path -Leaf $sourcePath
							$newDestFullPath=join-path $destPath $sourceChild
							$newbackupFilesorFolder=join-path $desbackuppath $sourceChild
							
							if((Test-Path $newDestFullPath) -and !(Test-Path $newbackupFilesorFolder)){
								#begin backup
								Move-Item -Path  $newDestFullPath -Destination $desbackuppath -Force  -Verbose -ErrorAction Stop

								$message="Backup $newDestFullPath successfully!"
								writeLogfile -context $message
								write-host $message 
							}
						}
						
						Copy-Item -Path  $sourcePath -Destination $destPath -Recurse -Force -Verbose -ErrorAction Stop
						
						$message="Copy items successfully!"
						writeLogfile -context $message
						write-host $message 
						Write-Host ""
					}
				}
				else{
					#the souce directory is wrong.
					$message=[string]::Format("{0} {1}","[ERROR]","The souce directory :$sourcePath is wrong.")
					writeLogfile -context $message
					Write-Host $message -ForegroundColor Red 
					Write-Host ""
				}
			}
		}
	}
	end{
	}
}

function transferPath{
	param([string]$servername,[string]$directory)
	begin{
	 $path=""
	}
	process{
		if($servername -eq "." -or $servername -eq ""){
			$path=$directory
		}
		else{
		    if(!$servername.contains("\\")){
				$servername= -join ("\\",$servername)
			}
			$path=Join-Path $servername $directory
			$path=$path.replace(":","$")
		}
	}
	end{
		return $path 
	}
}

#write log
function writeLogfile{
	param($context)
	process{
	    $context=[string]::Format("[{0},{1}] {2}","COPY FILE",(Get-Date),$context)  
		Out-File -FilePath $logpath -InputObject $context -Append -Encoding ASCII  -ErrorAction Stop 
	}
}

#initialize environment
initEvironment
#get the configration information
$configTaskDic=@{}
$configTaskDic=getConfigInfoDic -xmlpath $configpath
#copy file or directory process
copyFileProcess -configTaskDic $configTaskDic