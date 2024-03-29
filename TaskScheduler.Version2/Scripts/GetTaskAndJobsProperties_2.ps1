# Returns SCOM PropertyBags of Task Scheduler Tasks and PowerShell Scheduled Jobs
#
#	output is to be used both by discovery, monitors and rules
#
#	script will run with slightly reduced functionality on PS 2.0
#			(SCOM agent PS host remains on 2.0 even after Management Framework upgrade on W2k8R2)
#
#
# Version 1.0 - 09. May 2014 - initial            			  - Raphael Burri - raburri@bluewin.ch
# Version 2.0 - 04. June 2014 - added PSScheduledJob support  - Raphael Burri - raburri@bluewin.ch
# Version 2.1 - 19. June 2014 - made script more robust regarding legacy PowerShell (2.0).
# Version 2.2 - 15. April 2020 - MemoryLeak Fix in Get-WinEvent and comment Write-Host in Functions, now much slower - Bernhard Scherndl

param ( [string]$scriptName = 'Custom.TaskScheduler2.Task.GetTaskProperties.ps1',
		[string]$discoverWindowsTasks = 'false',
		[int]$lastRunDurationLookback = 900,
		[string]$debugParam = 'true'
		)

#get tasks from a folder; thenn drill down into subfolders
function Get-AllTasks
	{
	Param ([string]$path,
	[int]$lastRunDurationLookback,
	[int]$eventSupport) 

	$tasks = @()
   	#only fetch system tasks (folders in \Microsoft\Windows with the exception of PS scheduled jobs and Backup), if asked to
	If (($DiscoverWindowsTasks -eq $true) -or (($discoverWindowsTasks -eq $false) -and (($path -notmatch "^\\Microsoft\\Windows\\") -or ($path -match "^\\Microsoft\\Windows\\(Backup|PowerShell)\\"))))
		{
	   	# Get folder's root tasks
    	$schedule.GetFolder($path).GetTasks(0) | % `
			{
			$isPSScheduledJob = $false
			$TaskTriggerText = ""
			$TaskActionText = ""
			$TaskLastRuntime = -1
			$TaskLastRuntimeMinutes = -1
			$TaskRunningSince = -1
			$TaskLauchRequestSkipped = "False"
			
			$cleanTask = New-Object psobject
			$cleanTask | Add-Member -MemberType NoteProperty -Name Name -Value $_.Name
			$cleanTask | Add-Member -MemberType NoteProperty -Name Path -Value $_.Path
			$cleanTask | Add-Member -MemberType NoteProperty -Name Author -Value $_.Definition.RegistrationInfo.Author
			$cleanTask | Add-Member -MemberType NoteProperty -Name Description -Value $_.Definition.RegistrationInfo.Description
			$cleanTask | Add-Member -MemberType NoteProperty -Name User -Value $_.Definition.Principal.userId
			$cleanTask | Add-Member -MemberType NoteProperty -Name Hidden -Value $_.Definition.Settings.Hidden
			
			#if task runtime doesn't have a date then it actually hasn't ever run so far. The timestamp will be 12/30/1899 12:00:00 AM
			If (((Get-Date) - $_.LastRunTime).Days -lt 36500)
				{
				#no SCOM DB overloading --> return static text.
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastRunTime -Value "HasDate"
				}
			Else
				{
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastRunTime -Value "Never"
				}
			
			#likewise for next run (e.g. tasks without a schedule)
			If (((Get-Date) - $_.NextRunTime).Days -lt 36500)
				{
				#no SCOM DB overloading --> return static text.
				$cleanTask | Add-Member -MemberType NoteProperty -Name NextRunTime -Value "HasDate"
				}
			Else
				{
				$cleanTask | Add-Member -MemberType NoteProperty -Name NextRunTime -Value "NotDefined"
				}
			
			#if the task has not run so far then ignore the last result
			If ($cleanTask.LastRunTime -eq "Never") {
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastTaskResult -Value ""
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastTaskResultHex -Value ""
				}
			else {
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastTaskResult -Value $_.LastTaskResult
				$cleanTask | Add-Member -MemberType NoteProperty -Name LastTaskResultHex -Value ("0x" + ("{0:x8}" -f  $_.LastTaskResult))
				}
			
			$cleanTask | Add-Member -MemberType NoteProperty -Name State -Value $_.State
			#add text for state
			switch ($_.State) {
				0 {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value $TASK_STATE_0}
				1 {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value $TASK_STATE_1}
				2 {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value $TASK_STATE_2}
				3 {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value $TASK_STATE_3}
				4 {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value $TASK_STATE_4}
				default {$cleanTask | Add-Member -MemberType NoteProperty -Name StateText -Value "Unknown"}
				}
			#assume the task has no schedule based triggers	- overwrite if otherwise
			$cleanTask | Add-Member -MemberType NoteProperty -Name TaskIsScheduled -Value 'False'
			#build one string describing the triggers
			
			foreach ($trigger in $_.Definition.Triggers)
				{
				#trigger.Enabled gives localized output. As the monitors are later matching this for 'True' resp. 'False', this need to be changed into an english string
				If ($trigger.Enabled -eq $true) { $TriggerStateText = "True" }
				Else { $TriggerStateText = "False" }
				switch ($trigger.Type) {
					0 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_0 + " ||| "}
					1 {
						$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_1 + " ||| "
						if ($trigger.Enabled -eq $true) {$cleanTask | Add-Member -MemberType NoteProperty -Name TaskIsScheduled -Value 'True' -Force}
						}
					2 {
						$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_2 + " ||| "
						if ($trigger.Enabled -eq $true) {$cleanTask | Add-Member -MemberType NoteProperty -Name TaskIsScheduled -Value 'True' -Force}
						}
					3 {
						$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_3 + " ||| "
						if ($trigger.Enabled -eq $true) {$cleanTask | Add-Member -MemberType NoteProperty -Name TaskIsScheduled -Value 'True' -Force}
						}
					4 {
						$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_4 + " ||| "
						if ($trigger.Enabled -eq $true) {$cleanTask | Add-Member -MemberType NoteProperty -Name TaskIsScheduled -Value 'True' -Force}
						}
					5 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_5 + " ||| "}
					6 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_6 + " ||| "}
					7 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_7 + " ||| "}
					8 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_8 + " ||| "}
					9 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_TYPE_9 + " ||| "}
					11 {
						switch ($trigger.StateChange) {
							1 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_1 + " ||| "}
							2 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_2 + " ||| "}
							3 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_3 + " ||| "}
							4 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_4 + " ||| "}
							7 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_7 + " ||| "}
							8 {$TaskTriggerText = $TaskTriggerText + $TriggerStateText + ": " + $TRIGGER_STATE_CHANGE_8 + " ||| "}
							default {$TaskTriggerText = $TaskTriggerText + "Unknown (StateChange " + $trigger.StateChange + ") ||| "}
							}
						}
					default {$TaskTriggerText = $TaskTriggerText + "Unknown (Type " + $trigger.Type + ") ||| "}
					}
				}
			#clean up string
			if ($TaskTriggerText.length -gt 0) {$TaskTriggerText = ($TaskTriggerText.Substring(0,$TaskTriggerText.length - 5)).trim()}
			$cleanTask | Add-Member -MemberType NoteProperty -Name TriggerText -Value $TaskTriggerText
	
			#build one string describing the actions
			foreach ($action in $_.Definition.Actions) {
				switch ($action.type)	{
					0 {#check if it is a PSScheduledJob
						if (($cleanTask.path -imatch "^\\Microsoft\\Windows\\PowerShell\\") -and `
								($action.arguments -imatch "\[Microsoft\.PowerShell\.ScheduledJob\.ScheduledJobDefinition\]::LoadFromStore\("))
							{
							$isPSScheduledJob = $true
							}
						$TaskActionText = $TaskActionText + $TASK_ACTION_0 + ": " + $action.path + " " + $action.arguments + " ||| "
						}
					5 {$TaskActionText = $TaskActionText + $TASK_ACTION_5 + ": " + $action.classId + " " + $action.data + " ||| "}
					6 {$TaskActionText = $TaskActionText + $TASK_ACTION_6 + ": ""Server: " + $action.Server + ", " + `
								   "From: " + $action.From + ", " + `
								   "To: " + $action.To + ", " + `
								   "Cc:	" + $action.Cc + ", " + `
								   "Bcc: " + $action.Bcc + ", " + `
								   "Subject: " + $action.Subject + ", " + `
								   "Text:    " + $action.Body + """ ||| " 
					  }
					7 {$TaskActionText = $TaskActionText + $TASK_ACTION_7 + ": ""Title: " + $action.Title + ", " + `
								   "Text: " + $action.MessageBody + """ ||| "
						#message boxes always seem to return an exit code of 1. The MP will have to take this into account
					  }
					default {$TaskActionText = $TaskActionText + "Unknown (Type " + $action.Type + ") ||| "} 
					}
				}
			#clean up string
			if ($TaskActionText.length -gt 0) {$TaskActionText = ($TaskActionText.Substring(0,$TaskActionText.length - 5)).trim()}
			
			$cleanTask | Add-Member -MemberType NoteProperty -Name ActionText -Value $TaskActionText
			
			#last completed execution duration (from event log) and current run duration
			#     will be -1 if not applicable or task already running
			# get last end time from event log
			if (($lastRunDurationLookback -gt 0) -and ($eventSupport -eq 1))
				{
				$taskLastEndTime = (Get-TaskLastEndTime -taskPath $cleanTask.Path)
# We are rounding of $tasklastendtime total without decimal points
                #$taskLastEndTimeseconds[decimal]:::round((($taskLastEndTime).TotalSeconds),0)
				#if recently then get the longest run
				if (((((Get-Date) - ($taskLastEndTime)).TotalSeconds) -le $lastRunDurationLookback) -and ($_.State -gt 1))
					{
					#fetch the latest start events - lookback to allow getting the longest runtime on frequently running jobs
					$TaskLastStartEvents = @(Get-TaskLastRunDurations -taskPath $cleanTask.Path -lookbackSeconds $lastRunDurationLookback)
					#get the longest run observed during lookback timeframe from eventlog
					$TaskLastRuntimes = @($TaskLastStartEvents | Sort-Object @{Expression={$_.RunTimeSeconds}; Ascending=$false})
					[int]$TaskLastRuntime = $TaskLastRuntimes.Get(0).RunTimeSeconds

					[int]$TaskLastRuntimeMinutes = [decimal]::round(($TaskLastRuntime / 60),0)
#					Write-Host Observed $TaskLastRuntimes.Count end events of task $_.Name within the last $lastRunDurationLookback seconds. Longest RunTime of those was: $TaskLastRuntime seconds 
					
					#see if "launch request ignored" happened
					#     only reset skipped monitor if task ended WITHOUT a 322 event during its execution
					$TaskLastStartEvent = @($TaskLastStartEvents | Sort-Object @{Expression={$_.StartTime}; Ascending=$false}).Get(0)
					$taskLastLaunchSkipped = Get-TaskLastRunLaunchIgnored -taskPath $cleanTask.Path -lookbackSeconds $TaskLastStartEvent.RunTimeSeconds
					if ([datetime]$taskLastLaunchSkipped -gt [datetime]"1/1/1600")
						{
#						Write-Host Task launched skipped was observed during last run of task $_.Name at $taskLastLaunchSkipped
						$TaskLauchRequestSkipped = "True"
						}
					}
				}
			#fallback if no event support (PowerShell 1.0)
			if (($eventSupport -eq 0) -and ($_.State -gt 1))
				{
#				Write-Host -BackgroundColor Yellow -ForegroundColor Black WARNING: No exact runtime info as Get-WinEvent is not supported on PowerShell $PSVersionString
#				Write-Host -BackgroundColor Yellow -ForegroundColor Black `t estimating based on task''s LastRunTime - 120 seconds.
				#just estimate last runtime from task properties - not attempt to get the exact value from event log
				#   minus 120 seconds - this will be the minumal delay in calling script after task end event.
			[int]$TaskLastRuntime= ([decimal]::round(((Get-Date) - $_.LastRunTime).TotalSeconds, 0) -120)
		   [int]$TaskLastRuntimeMinutes = [decimal]::round(($TaskLastRuntime / 60),0)
				}	
			$cleanTask | Add-Member -MemberType NoteProperty -Name LastRunDurationSeconds -Value $TaskLastRuntime
			$cleanTask | Add-Member -MemberType NoteProperty -Name LastRunDurationMinutes -Value $TaskLastRuntimeMinutes
			$cleanTask | Add-Member -MemberType NoteProperty -Name LaunchRequestSkippedDuringExecution -Value $TaskLauchRequestSkipped
			
			#if currently running see how long
			if ($_.State -eq 4)
				{
				#get how long since it's been started from last run time property
				[int]$TaskRunningSince = [decimal]::round(((Get-Date) - $_.LastRunTime).TotalMinutes, 0)
				}	
			$cleanTask | Add-Member -MemberType NoteProperty -Name CurrentRunDurationMinutes -Value $TaskRunningSince
			
			#from SCOM perspective, scheduledtask and PSScheduledJob are mostly identical
			#   however; in order to check on their error, warning and output additional checking on their result.xml is required
			#   note: PSScheduledJob's return code will ALWAYS be 0, regardless of expcetions that might have been thrown.
			$cleanTask | Add-Member -MemberType NoteProperty -Name IsPSScheduledJob -Value $isPSScheduledJob
			if ($isPSScheduledJob -eq $true)
				{
				$psJobResult =  GetScheduledJobResult -scheduledTaskActionParameter $cleanTask.ActionText
				if ($psJobResult -ne $null)
					{
					#overwrite actiontext with PS scriptblock
					$actionText = ($TASK_ACTION_0_PS + ": " + $psJobResult.PSJobCommand)
					$cleanTask | Add-Member -MemberType NoteProperty -Name ActionText -Value $actionText -Force
					#specific PSScheduledJob properties
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobName -Value $psJobResult.PSJobName
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobCommand -Value $psJobResult.PSJobCommand
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputCount -Value $psJobResult.PSJobOutputCount
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputTypes -Value $psJobResult.PSJobOutputTypes
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputContent -Value $psJobResult.PSJobOutputContent
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobErrorCount -Value $psJobResult.PSJobErrorCount
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobErrorContent -Value $psJobResult.PSJobErrorContent
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobWarningCount -Value $psJobResult.PSJobWarningCount
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobWarningContent -Value $psJobResult.PSJobWarningContent
				
					}
				}
			else
				{   #return empty strings for classic tasks
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobName -Value ""
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobCommand -Value ""
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputCount -Value 0
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputTypes -Value ""
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobOutputContent -Value ""
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobErrorCount -Value 0
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobErrorContent -Value ""
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobWarningCount -Value 0
					$cleanTask | Add-Member -MemberType NoteProperty -Name PSJobWarningContent -Value ""
				}
			#debug output to event log
			if ($debugParam -eq $true)
				{
				$cleanTaskOutput = "
Task Scheduler Task
-----------
Name: " + [string]$cleanTask.Name + "
Path: " + [string]$cleanTask.Path + "
Author: " + [string]$cleanTask.Author + "
User: " + [string]$cleanTask.User + "
IsPSScheduledJob: " + [string]$cleanTask.IsPSScheduledJob + "

Hidden: " + [string]$cleanTask.Hidden + "
LastRunTime: " + [string]$cleanTask.LastRunTime + "
NextRunTime: " + [string]$cleanTask.NextRunTime + "
LastTaskResult: " + [string]$cleanTask.LastTaskResult + "
LastTaskResultHex: " + [string]$cleanTask.LastTaskResultHex + "
State: " + [string]$cleanTask.State + "
StateText: " + [string]$cleanTask.StateText  +  "
TaskIsScheduled: " + [string]$cleanTask.TaskIsScheduled + "
TriggerText: " + [string]$cleanTask.TriggerText + "
ActionText: " + [string]$cleanTask.ActionText + "

LastRunDurationSeconds: " + [string]$cleanTask.LastRunDurationSeconds + "
LastRunDurationMinutes: " + [int]$cleanTask.LastRunDurationMinutes + "
CurrentRunDurationMinutes: " + [int]$cleanTask.CurrentRunDurationMinutes + "
LaunchRequestSkipped: " + [string]$cleanTask.LaunchRequestSkippedDuringExecution + "

PSJobName: " + [string]$cleanTask.PSJobName + "
PSJobCommand: " + [string]$cleanTask.PSJobCommand + "
PSJobOutputCount: " + [string]$cleanTask.PSJobOutputCount + "
PSJobErrorCount: " + [string]$cleanTask.PSJobErrorCount + "
PSJobErrorContent: " + [string]$cleanTask.PSJobErrorContent + "
PSJobWarningCount: " + [string]$cleanTask.PSJobWarningCount

				$objAPI.LogScriptEvent($scriptName, 9625, 4, "DEBUG: " + $cleanTaskOutput)
				}	
	
#			Write-Host adding task $cleanTask.Path
			$tasks += @($cleanTask)
			}	    
    	}

    # Get tasks from subfolders
    $schedule.GetFolder($path).GetFolders(0) | % {
		$tasks += @(Get-AllTasks -path $_.Path -lastRunDurationLookback $lastRunDurationLookback -eventSupport $eventSupport)
    	}

    #Output
    Return $tasks
}

function Get-TaskLastEndTime {
	param ([string]$taskPath)
	#fetch the most recent success event (102) or failed (111) event that occured within a timeframe
	# in case taskpath contains quotes, have to escape (double) them
	$taskPath = $taskPath.Replace("'","''")
	$successXPath = "*[System[((EventID=102) or (EventID=111))]] and *[EventData[Data[1]='" + $taskPath + "']]"
#	$taskSuccessEvent = get-winevent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $successXPath -MaxEvents 1 -ErrorAction SilentlyContinue
	$taskSuccessEvent = get-winevent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $successXPath -ErrorAction SilentlyContinue
	#$query = New-Object -TypeName System.Diagnostics.Eventing.Reader.EventLogQuery -ArgumentList @('Microsoft-Windows-TaskScheduler/Operational', 1, $successXPath)
    #$reader = New-Object -TypeName System.Diagnostics.Eventing.Reader.EventLogReader -ArgumentList $query
   # $taskSuccessEvent = $reader.ReadEvent()
    
    #$reader.Dispose()
	if ($taskSuccessEvent)
		{
		return $taskSuccessEvent[0].TimeCreated
		}
	else
		{
		#no end event found within the timeframe; return null
		return [datetime]"1/1/1600"
		}
	}

# get all task start events and their start times that occured within the last n seconds
function Get-TaskLastRunDurations {
	param ([string]$taskPath, [int]$lookbackSeconds)
	
	$taskDurations = @()
	# in case taskpath contains quotes, have to escape (double) them
	$taskPath = $taskPath.Replace("'","''")
	#fetch the most recent success (102) or terminated (111) events that occured within a timeframe
	$successXPath = "*[System[((EventID=102) or (EventID=111)) and TimeCreated[timediff(@SystemTime) <= " + $lookbackSeconds * 1000 + "]]] and *[EventData[Data[1]='" + $taskPath + "']]"
	$taskSuccessEvents = @(get-winevent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $successXPath -ErrorAction SilentlyContinue)
	if ($taskSuccessEvents.Count -gt 0)
		{
		foreach ($taskSuccessEvent in $taskSuccessEvents)
			{
			$taskDuration = New-Object psobject
			$taskDuration | Add-Member -MemberType NoteProperty -Name EndTime -Value $taskSuccessEvent.TimeCreated		
			#get start event (100) with the same TaskName and InstanceId
			$global:taskSuccessEvent = $taskSuccessEvent
			#InstanceId is 3rd on 102 event / 2nd on 111 event
			if ($taskSuccessEvent.Id -eq 102) {$taskInstanceId = $taskSuccessEvent.Properties[2].Value.ToString()}
			else {$taskInstanceId = $taskSuccessEvent.Properties[1].Value.ToString()}
			$startXPath = "*[System[(EventID=100)]] and *[EventData[(Data[1]='" + $taskSuccessEvent.Properties[0].Value.ToString().Replace("'","''") + "' and Data[3]='{" + $taskInstanceId + "}')]]"
#			$taskStartEvent = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $startXPath -MaxEvents 1 -ErrorAction SilentlyContinue
			$taskStartEvent = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $startXPath -ErrorAction SilentlyContinue
			if ($taskStartEvent) 
				{
                $taskStartEvent = $taskStartEvent[0]
				$taskDuration | Add-Member -MemberType NoteProperty -Name StartTime -Value $taskStartEvent.TimeCreated
				$taskRunTimeSeconds = [decimal]::round(($taskSuccessEvent.TimeCreated - $taskStartEvent.TimeCreated).TotalSeconds, 0)		
				}
			else
				{
				#no start event found within the timeframe; set duration to -1
				$taskDuration | Add-Member -MemberType NoteProperty -Name StartTime -Value "unknown"
				$taskRunTimeSeconds = -1
				}
			$taskDuration | Add-Member -MemberType NoteProperty -Name RunTimeSeconds -Value $taskRunTimeSeconds
			$taskDurations += $taskDuration
			}
		}
	return $taskDurations
	}

function Get-TaskLastRunLaunchIgnored {
	param ([string]$taskPath, [int]$lookbackSeconds)
	
	#fetch the most recent "Launch request ignored, instance already running" event occured during last execution) that occured within a timeframe
	# in case taskpath contains quotes, have to escape (double) them
	$taskPath = $taskPath.Replace("'","''")
	$ignoredXPath = "*[System[(EventID=322) and TimeCreated[timediff(@SystemTime) <= " + $lookbackSeconds * 1000 + "]]] and *[EventData[(Data[1]='" + $taskPath + "')]]"
#	$taskIgnoredEvent = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $ignoredXPath -MaxEvents 1 -ErrorAction SilentlyContinue 
	$taskIgnoredEvent = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -FilterXPath $ignoredXPath -ErrorAction SilentlyContinue
	#$query = New-Object -TypeName System.Diagnostics.Eventing.Reader.EventLogQuery -ArgumentList @('Microsoft-Windows-TaskScheduler/Operational', 1, $ignoredXPath)
   # $reader = New-Object -TypeName System.Diagnostics.Eventing.Reader.EventLogReader -ArgumentList $query
    #$taskSuccessEvent = $reader.ReadEvent()
   # $reader.Dispose()

	if ($taskIgnoredEvent)
		{
		return [datetime]$taskIgnoredEvent.TimeCreated
		}
	else
		{
		#no launch ignored event found within the timeframe; return null
		return [datetime]"1/1/1600"
		}
	}

#PSScheduledJob related functions
function GetScheduledJobResult
	{
	param ([string]$scheduledTaskActionParameter)
	$jobName = $null
	$jobCommand = $null
	$scheduledJobDefinitionStrings = GetScheduledJobDefinitionStrings -scheduledTaskCommand $scheduledTaskActionParameter
	#see if jobdefinition can be loaded (PS >=3.0)
	#    if not (running on PS 2.0), extract the jobName from the task action string
	try {
		#import module to get full support
		if (-not (Get-Module -Name PSScheduledJob))	{Import-Module PSScheduledJob}
		$jobDefinition = [Microsoft.PowerShell.ScheduledJob.ScheduledJobDefinition]::LoadFromStore($scheduledJobDefinitionStrings.Item("jobdefname"), $scheduledJobDefinitionStrings.Item("jobdefpath"))
		$jobName = $jobDefinition.Name
		$jobCommand = $jobDefinition.Command
		}
	catch {
		#when on PS2.0 (SCOM host) LoadFromStore will not work
		$jobName = $scheduledJobDefinitionStrings.Item("jobdefname")
		$jobCommand = $null
		}
	
	$jobResult = New-Object psobject
	$jobResult | Add-Member -MemberType NoteProperty -Name PSJobName -Value $jobName
	$jobResult | Add-Member -MemberType NoteProperty -Name PSJobCommand -Value $jobCommand
				
	#as accessing job results isn't possible for a different user using PSScheduledJob module,
	#   go ahead and parse Results.xml directly
	[string]$jobOutputFolder = ($scheduledJobDefinitionStrings.Item("jobdefpath").Trim() + "\" + $scheduledJobDefinitionStrings.Item("jobdefname").Trim() + "\Output")
	#sort the output files according to their "Status_StopTime" value
	$sortedResultFiles = @(Get-ChildItem $JobOutputFolder -Recurse -Filter "Results.xml" |
		Sort-Object @{Expression={[System.DateTime]([xml](Get-Content -Path $_.FullName -ErrorAction SilentlyContinue)).ScheduledJob.StatusInfo.Status_StopTime.InnerText}; Ascending=$false})	
	#load most recent Results.xml and get result details from it
	if ($sortedResultFiles.Count -gt 0)
		{
		[xml](Get-Content -Path ($sortedResultFiles.Get(0)).FullName -ErrorAction SilentlyContinue) |
			% {
			#in case loading definition failed, attempt to extract name and command from Results.xml
			#    note: will only work if job has ran at least once
			if ($jobName -eq $null) {$jobResult | Add-Member -MemberType NoteProperty -Name PSJobName -Value ($_.ScheduledJob.StatusInfo.Status_Name.InnerText) -Force }
			if ($jobCommand -eq $null) {$jobResult | Add-Member -MemberType NoteProperty -Name PSJobCommand -Value ($_.ScheduledJob.StatusInfo.Status_Command.InnerText) -Force }
			$jobInstanceId = [System.Guid]$_.ScheduledJob.StatusInfo.Status_InstanceId.InnerText
			#should be completed always as it has a StopTime value
			$jobStatus = [System.Management.Automation.JobState]$_.ScheduledJob.StatusInfo.Status_State.InnerText
			$jobStartTime = [System.DateTime]$_.ScheduledJob.StatusInfo.Status_StartTime.InnerText
			$jobEndTime = [System.DateTime]$_.ScheduledJob.StatusInfo.Status_StopTime.InnerText
			$jobRunTimeMinutes = [decimal]::round(($jobEndTime - $jobStartTime).TotalMinutes, 2)
			
			#Results to objects built of strings (so SCOM can work with them)
			$outputItems = GetScheduledJobXMLItemsDetail -resultsType "Output" -xmlElement $_.ScheduledJob.ResultsInfo.Results_Output
			$errorItems = GetScheduledJobXMLItemsDetail -resultsType "Error" -xmlElement $_.ScheduledJob.ResultsInfo.Results_Error
			$warningItems = GetScheduledJobXMLItemsDetail -resultsType "Warning" -xmlElement $_.ScheduledJob.ResultsInfo.Results_Warning
					
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobStatus -Value $jobStatus
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobLastRunDurationMinutes -Value $jobRunTimeMinutes
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobOutputCount -Value $outputItems.Size
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobOutputTypes -Value $outputItems.ItemTypes
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobOutputContent -Value $outputItems.ItemContents
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobErrorCount -Value $errorItems.Size
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobErrorContent -Value $errorItems.ItemContents
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobWarningCount -Value $warningItems.Size
			$jobResult | Add-Member -MemberType NoteProperty -Name PSJobWarningContent -Value $warningItems.ItemContents
			}
		}
	return $jobResult
	}

function GetScheduledJobDefinitionStrings
	{
	#get jobdefinitionname and jobdefinitionpath from the scheduled task's command line
	param ($scheduledTaskCommand)
	$scheduledJobDefMatch = "\[Microsoft\.PowerShell\.ScheduledJob\.ScheduledJobDefinition\]::LoadFromStore\(('|"")(?<jobname>.+)('|""),.*('|"")(?<jobstore>.+)('|"")\)"
	$scheduledTaskCommand -match $scheduledJobDefMatch | Out-Null
	# make sure double quotes are replaced
	return @{"jobdefname" = ($Matches.jobname).Replace("''", "'"); "jobdefpath" = ($Matches.jobstore).Replace("''", "'")}
	}
	
function GetScheduledJobXMLItemsDetail
	{
	#get details as count and string of deserialized output.xml content.
	#   deserialization will fail not work on PS 2.0; just count will be available
	param ([string]$resultsType, [System.Xml.XmlElement]$xmlElement)
	
	$itemCount = 0
	$allItemTypeString = ""
	$allItemContentString = ""
	if ($resultsType -eq "Warning") {$global:xmlElement = $xmlElement}
	
	if ($xmlElement.items._items.Size -gt 0)
		{
		foreach ($item in $xmlElement.items._items.ChildNodes)
			{
			#undo CliXML to get original object back
			if ($item.IsEmpty -eq $false)
				{
				$itemCount ++
				
				#PS 3.0 and later support Deserialize so we can get the actual objects and see about presenting them in string
				#     note: PS 1.0 workflows (Windows 2008) will never suppport PS Scheduled Jobs (requires PS >=3.0 be installed)
				#     on Windows 2008 R2 this script may run in 2.0 even when >=3.0 are installed locally (SCOM agent limitation).
				if ([string]$PSVersionTable.PSVersion -notmatch "^2\.")
					{
					switch ($resultsType) {
					"Output" {
						$itemDeserialized = [System.Management.Automation.PSSerializer]::Deserialize($item.clixml.InnerText)
						#return the type
						$itemTypeString = $null
						#some items do not support GetType() but have a ToSting()
						try { $itemTypeString = $itemDeserialized.GetType().FullName }
						catch {
							try { $itemTypeString = $itemDeserialized.ToString() }
							catch {$itemTypeString = "UnknownObject" }
						}
						$allItemTypeString = $allItemTypeString + $itemTypeString + " ||| "
						
						#see if the object can be converted to string (e.g. script output)
						try {
							$itemContentString = [System.String]$itemDeserialized
							}
						catch	{
							$itemContentString = [System.String]"'" + ($itemDeserialized.GetType().FullName) + "' can not be converted to a string object."
							}
						#truncate output if longer than 1024 characters
						if ($itemContentString.length -gt 1024) {$itemContentString = $itemContentString.Substring(0, 1024).trim()}
						$allItemContentString = $allItemContentString + $itemContentString + " ||| "
						}
					"Error" {
						$itemDeserialized = [System.Management.Automation.PSSerializer]::Deserialize($item.clixml.InnerText)
						
						#return the type
						$allItemTypeString = $allItemTypeString + $itemDeserialized.Exception.SerializedRemoteInvocationInfo.InvocationName + " ||| "
						#see if the exception can be converted to string (e.g. script output)
						try {
							$itemContentString = [System.String]$itemDeserialized.Exception.SerializedRemoteException
							}
						catch	{
							$itemContentString = [System.String]"Exception can not be converted to a string object."
							}
						if ($itemContentString.length -gt 1024) {$itemContentString = $itemContentString.Substring(0, 1024).trim()}
						$allItemContentString = $allItemContentString + $itemContentString + " ||| "
						}
					"Warning" {
						#warning seems to be string natively
						$allItemTypeString = $allItemTypeString + "System.Management.Automation.WarningRecord" + " ||| "
						
						#see if the warning record can be converted to string
						try {
							$itemContentString = [System.String]$item.message.'#text'
							}
						catch	{
							$itemContentString = [System.String]"Warning can not be converted to a string object."
							}
						#truncate output if longer than 1024 characters
						if ($itemContentString.length -gt 1024) {$itemContentString = $itemContentString.Substring(0, 1024).trim()}
						$allItemContentString = $allItemContentString + $itemContentString + " ||| "
						}
					}		
					}
				}
			}
			#clean last separator and shorten to a total of 8192 characters
			if ($allItemTypeString.length -gt 0) {
				$allItemTypeString = ($allItemTypeString.Substring(0,$allItemTypeString.length - 5)).trim()
				if ($allItemTypeString.length -gt 8192) {$allItemTypeString = $allItemTypeString.Substring(0, 8192)}
				}
			if ($allItemContentString.length -gt 0) {
				$allItemContentString = ($allItemContentString.Substring(0,$allItemContentString.length - 5)).trim()
				if ($allItemContentString.length -gt 8192) {$allItemContentString = $allItemContentString.Substring(0, 8192)}
				}
		}	
	$itemDetail = New-Object psobject
	$itemDetail | Add-Member -MemberType NoteProperty -Name ResultsType -Value $resultsType
	$itemDetail | Add-Member -MemberType NoteProperty -Name Size -Value $itemCount
	$itemDetail | Add-Member -MemberType NoteProperty -Name ItemTypes -Value $allItemTypeString
	$itemDetail | Add-Member -MemberType NoteProperty -Name ItemContents -Value $allItemContentString
	
	Return $itemDetail
	}


#region constvar
#constants & variables
$TASK_STATE_0 = "Unknown"
$TASK_STATE_1 = "Disabled"
# make 2, 3 and 4 use the SAME string (to avoid changing SCOM objet properties too often)
#$TASK_STATE_2 = "Queued""
$TASK_STATE_2 = "Ready / Queued / Running"
#$TASK_STATE_3 = "Ready""
$TASK_STATE_3 = "Ready / Queued / Running"
#$TASK_STATE_4 = "Running"
$TASK_STATE_4 = "Ready / Queued / Running"

$TASK_ACTION_0 = "Start a program" 		#"Exec" 		Represents an action that executes a command-line operation
$TASK_ACTION_0_PS = "PS job"		    #""Exec"        Added to allow flagging PSJobs
$TASK_ACTION_5 = "Custom handler" 		#"ComHandler"	This action fires a handler
$TASK_ACTION_6 = "Send an e-mail"		#"This action sends an e-mail"
$TASK_ACTION_7 = "Display a message" 	#"ShowMessage"	This action shows a message box


$TRIGGER_TYPE_0 = "On event" 							#"TASK_TRIGGER_EVENT" 				'"Starts the task when a specific event occurs"
$TRIGGER_TYPE_1 = "One time" 							#"TASK_TRIGGER_TIME" 					'"Starts the task at a specific time of day"
$TRIGGER_TYPE_2 = "Daily" 								#"TASK_TRIGGER_DAILY" 				'"Starts the task daily"
$TRIGGER_TYPE_3 = "Weekly" 								#"TASK_TRIGGER_WEEKLY" 				'"Starts the task weekly"
$TRIGGER_TYPE_4 = "Monthly" 							#"TASK_TRIGGER_MONTHLY" 				'"Starts the task monthly"
$TRIGGER_TYPE_5 = "Monthly at day of week"  			#"TASK_TRIGGER_MONTHLYDOW" 			'"Starts the task every month on a specific day of the week"
$TRIGGER_TYPE_6 = "On idle" 							#"TASK_TRIGGER_IDLE" 					'"Starts the task when the computer goes into an idle state"
$TRIGGER_TYPE_7 = "At task creation/modification" 		#"TASK_TRIGGER_REGISTRATION" 			'"Starts the task when the task is registered"
$TRIGGER_TYPE_8 = "At startup" 							#"TASK_TRIGGER_BOOT" 					'"Starts the task when the computer boots"
$TRIGGER_TYPE_9 = "At log on" 							#"TASK_TRIGGER_LOGON" 				'"Starts the task when a specific user logs on"
$TRIGGER_TYPE_11 = "TASK_TRIGGER_SESSION_STATE_CHANGE"	#"Triggers the task when a specific session state changes"
$TRIGGER_STATE_CHANGE_1 = "On connection to console session"		#TASK_CONSOLE_CONNECT
$TRIGGER_STATE_CHANGE_2 = "On disconnect from console session"		#TASK_CONSOLE_DISCONNECT
$TRIGGER_STATE_CHANGE_3 = "On connect to user session"				#TASK_REMOTE_CONNECT
$TRIGGER_STATE_CHANGE_4 = "On disconnect from user session"			#TASK_REMOTE_DISCONNECT
$TRIGGER_STATE_CHANGE_7 = "On workstation lock"						#TASK_SESSION_LOCK
$TRIGGER_STATE_CHANGE_8 = "On workstation unlock"					#TASK_SESSION_UNLOCK
#endregion

#region SCOMvar
#prepare SCOM stuff
$objAPI = New-Object -ComObject "MOM.ScriptAPI"
#convert SCOM "text" boolean
if ($discoverWindowsTasks -eq 'true') {$discoverWindowsTasks = $true} else {$discoverWindowsTasks = $false}
if ($debugParam -eq 'true') {$debugParam = $true} else {$debugParam = $false}
#endregion

#region main
#debug output with calling parameters & PS environment
if ($debugParam -eq $true)
	{
	$objAPI.LogScriptEvent($scriptName, 9620, 4, "DEBUG: Calling script:

Parameter
------------
discoverWindowsTasks: " + [string]$discoverWindowsTasks + "
lastRunDurationLookback: " + [string]$lastRunDurationLookback + "

Environment
-------------
OS Version: " + [System.Environment]::OSVersion.VersionString + "
PS Version: " + [string]$PSVersionTable.PSVersion + "
PS Host Name: " +  [string]$host.Name + "
PS Host Version: " + [string]$host.Version)
	}
	
#check if running on Windows 6.x (Server 2008 / Vista) or higher
if ([System.Environment]::OSVersion.Version.Major -lt 6) {
	if ($debugParam -eq $true) {$objAPI.LogScriptEvent($scriptName, 9621, 2, "DEBUG: Script returning empty bag as it is running on Windows " + [System.Environment]::OSVersion.VersionString + ". Windows 6.0 and higher are supported (>= Server 2008 / Vista). For legacy OS the Custom.Windows.TaskScheduler.Windows2003.Monitoring MP can be used.")}
	#return an empty property bag (make undiscovery possible)
	$objTaskBag = $objAPI.CreatePropertyBag() 
	$objTaskBag
	exit 0
	}

#what PowerShell version we're on?
#    need PS 1.0 workable (doesn't know the PSVersionTable)
#what PowerShell version we're on?
$PSVersionString = [string]$PSVersionTable.PSVersion
if (!$PSVersionString) {$PSVersionString = "1.0"}

# no PS 1.0 support in SCOM 2012!
#if PS 1.0 is running on Windows 2008 (6.0) then warn and disable event support
#if (($PSVersionString -match "^1\.") -and ([System.Environment]::OSVersion.Version.Major -eq 6) -and ([System.Environment]::OSVersion.Version.Minor -eq 0))
#	{
#	$windowsEventSupport = 0
#	$objAPI.LogScriptEvent($scriptName, 9622, 2, "WARNING: Script running in PowerShell version " + $PSVersionString + " on " + [System.Environment]::OSVersion.VersionString + ".
#
#In order to fully support this management pack, consider upgrading PowerShell via ""Windows Management Framework"" to 2.0 or 3.0.
#
#As is, the MP will note be able to collect the task's exact execution time. Instead an estimated value will be returned.")
#	}

# PS 2.0 is running on Windows Server 2008 or 2008 R2; just inform in debug mode 
if ( ($debugParam -eq $true) -and ($PSVersionString -match "^2\.") -and ([System.Environment]::OSVersion.Version.Major -eq 6) -and ([System.Environment]::OSVersion.Version.Minor -le 1))
	{
	$windowsEventSupport = 1
	$objAPI.LogScriptEvent($scriptName, 9623, 4, "INFORMATION: Script running in PowerShell version " + $PSVersionString + " on " + [System.Environment]::OSVersion.VersionString + ".

PS Scheduled Job monitors will not be showing details on the nature of PS exceptions but return simply the number of exceptions that occured.

Note: SCOM 2012 agents on Windows Server 2008 and 2008 R2 will run PowerShell code in a 2.0 host even if PowerShell 3.0 or later is installed. SCOM management servers and gateways will use higher versions if it is installed locally.")
	}
else {$windowsEventSupport = 1}

#getting scheduled task info in PowerShell 1.0 and 2.0 requires COM object "Schedule.Service"
#    the cmdlets were only introduced in Server 2012 / Windows 8
#    as this script needs to run on Server 2008 / Vista as well just continue to use
#    COM.
$ErrorActionPreference = "SilentlyContinue"
$schedule = New-Object -ComObject "Schedule.Service"
$schedule.Connect() 

$objRootFolder = $schedule.GetFolder("\")
$ErrorActionPreference = "Continue"
If (($schedule -eq $null) -or ($objRootFolder.Name -eq ""))
	{
	#failed to connect this time. Write a warning and quit.
	#Keeps OpsMgr from deleting already discovered objects if the provider fails temporarily
	$objAPI.LogScriptEvent($scriptName, 9624, 2, "WARNING: Discovery script failed to access the Task Scheduler COM object ""Schedule.Service"". It is exiting without writing data.")
	}
Else
	{
	#enumerate root folder
	$tasks = @(Get-AllTasks -path $objRootFolder.Path -lastRunDurationLookback $lastRunDurationLookback -eventSupport $windowsEventSupport)
	if ($tasks.Count -gt 0) {
		foreach ($task in $tasks)
			{
			#build a SCOM property bag
			$objTaskBag = $objAPI.CreatePropertyBag() 
			$objTaskBag.AddValue("IsPSScheduledJob", [string]$task.IsPSScheduledJob)
			$objTaskBag.AddValue("Name", [string]$task.Name)
			$objTaskBag.AddValue("Path", [string]$task.Path)
			$objTaskBag.AddValue("Author", [string]$task.Author)
			$objTaskBag.AddValue("User", [string]$task.User)
			$objTaskBag.AddValue("Description", [string]$task.Description)
			$objTaskBag.AddValue("Hidden", [string]$task.Hidden)
			$objTaskBag.AddValue("LastRunTime", [string]$task.LastRunTime)
			$objTaskBag.AddValue("NextRunTime", [string]$task.NextRunTime)
			$objTaskBag.AddValue("LastTaskResult", [string]$task.LastTaskResult)
			$objTaskBag.AddValue("LastTaskResultHex", [string]$task.LastTaskResultHex)
			$objTaskBag.AddValue("State", [int]$task.State)
			$objTaskBag.AddValue("StateText", [string]$task.StateText)
			$objTaskBag.AddValue("TaskIsScheduled", [string]$task.TaskIsScheduled)
			$objTaskBag.AddValue("TriggerText", [string]$task.TriggerText)
			$objTaskBag.AddValue("ActionText", [string]$task.ActionText)
			$objTaskBag.AddValue("LastRunDurationSeconds", [double]$task.LastRunDurationSeconds)
			$objTaskBag.AddValue("LastRunDurationMinutes", [int]$task.LastRunDurationMinutes)
			$objTaskBag.AddValue("CurrentRunDurationMinutes", [int]$task.CurrentRunDurationMinutes)
			$objTaskBag.AddValue("LaunchRequestSkipped", [string]$task.LaunchRequestSkippedDuringExecution)	
			$objTaskBag.AddValue("DiscoverWindowsTasksSetting", [string]$discoverWindowsTasks)
			#PSscheduledJob
			$objTaskBag.AddValue("PSJobName", [string]$task.PSJobName)
			$objTaskBag.AddValue("PSJobCommand", [string]$task.PSJobCommand)
			$objTaskBag.AddValue("PSJobOutputCount", [int]$task.PSJobOutputCount)
			$objTaskBag.AddValue("PSJobOutputTypes", [string]$task.PSJobOutputTypes)
			$objTaskBag.AddValue("PSJobOutputContent", [string]$task.PSJobOutputContent)
			$objTaskBag.AddValue("PSJobErrorCount", [int]$task.PSJobErrorCount)
			$objTaskBag.AddValue("PSJobErrorContent", [string]$task.PSJobErrorContent)
			$objTaskBag.AddValue("PSJobWarningCount", [int]$task.PSJobWarningCount)
			$objTaskBag.AddValue("PSJobWarningContent", [string]$task.PSJobWarningContent)
			$objTaskBag
			}
		}
	else {
		#return an empty property bag (make undiscovery possible)
		$objTaskBag = $objAPI.CreatePropertyBag() 
		$objTaskBag
		}
	}

# Close com (fails on PS 1.0)
$ErrorActionPreference = "SilentlyContinue"
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($schedule) | Out-Null
Remove-Variable schedule

Remove-Variable debugParam
Remove-Variable discoverWindowsTasks
Remove-Variable foreach
Remove-Variable lastRunDurationLookback
Remove-Variable objAPI
Remove-Variable objRootFolder
Remove-Variable objTaskBag
Remove-Variable PSVersionString
Remove-Variable schedule
Remove-Variable scriptName
Remove-Variable startvars
Remove-Variable task
Remove-Variable TASK_ACTION_0
Remove-Variable TASK_ACTION_0_PS
Remove-Variable TASK_ACTION_5
Remove-Variable TASK_ACTION_6
Remove-Variable TASK_ACTION_7
Remove-Variable TASK_STATE_0
Remove-Variable TASK_STATE_1
Remove-Variable TASK_STATE_2
Remove-Variable TASK_STATE_3
Remove-Variable TASK_STATE_4
Remove-Variable tasks
Remove-Variable taskSuccessEvent
Remove-Variable TRIGGER_STATE_CHANGE_1
Remove-Variable TRIGGER_STATE_CHANGE_2
Remove-Variable TRIGGER_STATE_CHANGE_3
Remove-Variable TRIGGER_STATE_CHANGE_4
Remove-Variable TRIGGER_STATE_CHANGE_7
Remove-Variable TRIGGER_STATE_CHANGE_8
Remove-Variable TRIGGER_TYPE_0
Remove-Variable TRIGGER_TYPE_1
Remove-Variable TRIGGER_TYPE_11
Remove-Variable TRIGGER_TYPE_2
Remove-Variable TRIGGER_TYPE_3
Remove-Variable TRIGGER_TYPE_4
Remove-Variable TRIGGER_TYPE_5
Remove-Variable TRIGGER_TYPE_6
Remove-Variable TRIGGER_TYPE_7
Remove-Variable TRIGGER_TYPE_8
Remove-Variable TRIGGER_TYPE_9
Remove-Variable windowsEventSupport


