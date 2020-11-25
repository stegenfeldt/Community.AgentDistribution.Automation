Set-PSDebug -Strict

function Get-SCOMFailoverResourcePools
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string]
        $Prefix
    )

    Begin
    {
    }
    Process
    {
        $rps = Get-SCOMResourcePool -DisplayName "$($Prefix)*"
    }
    End
    {
        return $rps
    }
}

function Get-SCOMMResourcePoolMembers
{
    [CmdletBinding()]
    Param
    (
        # ResourcePool help description
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $ResourcePool
    )

    Begin
    {
        $members = $rp.Members
        $scomMSs = New-Object -TypeName System.Collections.ArrayList
    }
    Process
    {
        foreach ($member in $members)
        {
            $omms = Get-SCOMManagementServer -Name $member.DisplayName
            if ($null -ne $omms) {
                $scomMSs.Add($omms) | Out-Null
            }
        }
    }
    End
    {
        return $scomMSs
    }
}

function Update-SCOMAgentDistribution {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$ManagementServers,

        [string]$ComputerName = "."
    )

    <### Connect to SCOM 2012 Management Group ###
    Import-Module -Name "OperationsManager"
    New-SCOMManagementGroupConnection -ComputerName $ComputerName
    ### END ###>

    [array]$scomMSs = @()
    [array]$scomAgents = @()
    [hashtable]$agentSettings = @{}

    # Some variable to temporary store data in while neccesary.
    # "Defining" them like this is not really something you must do, but it helps
    # while development and troubleshooting.
    [array]$tempAgents = @()
    [int]$tempAgentCount = 0
    $tempAgent = $null

    # Not really neccesary, but ensures that we only have actual MSs to work with.
    # Add filtering if you need to or exchange Get-SCOMManagementServer
    # with Get-SCOMGatewayManagementServer to only get gateway servers.
    #$scomMSs = Get-SCOMManagementServer -Name $ManagementServerList
    $scomMSs = $ManagementServers
    #Write-Output -InputObject "Working with OMMS: `n`t`t$($scomMSs.Name)"

    #Gather all agents to avoid multiple trips to the SDK-service later on
    Foreach ($scomMS in $scomMSs) {
	    $tempAgents = @(Get-SCOMAgent -ManagementServer $scomMS)
	    if ($tempAgents.Count -gt 0) {
		    # I do this check because an empty management server (new perhaps)
		    # will return one $null item which will get added to the $scomAgents
		    # array. Giving you too many items in the $scomAgents array, ruining the
		    # averaging calculation.
		    $scomAgents += $tempAgents
	    }
    }

    [array]$belowAverageMS = @()
    [array]$movableAgents = @()
    [array]$tempAgents = @()
    # Average agents, always "rounded" down to nearest whole number
    $averageAgents = [math]::Floor($scomAgents.Count / $scomMSs.Count)
    # $modAgents will be the "left-overs" after the flooring.
    $modAgents = $scomAgents.Count % $scomMSs.Count
    #Write-Output -InputObject "Average Agents: $averageAgents"
    #Write-Output -InputObject "Rest: $modAgents"

    Foreach ($scomMS in $scomMSs) {
	    $tempAgents = $scomAgents | where{$_.PrimaryManagementServerName -eq $scomMS.Name}
	    [int]$tempAgentCount = $tempAgents.Count
	    if ($tempAgentCount -gt $averageAgents) {
		    $tempAgents = ($scomAgents | where {($_.PrimaryManagementServerName -eq $scomMS.Name) -and ($_.ManuallyInstalled -eq $false)})
		    if ($modAgents -gt 0){
			    $agentDiff = [int]($tempAgentCount - $averageAgents - 1)
			    $modAgents--
		    } else {
			    $agentDiff = [int]($tempAgentCount - $averageAgents)
		    }
		    if ($agentDiff -ge 1) {
			    # We're picking movable agents at random here to minimize the risk that
			    # the same agents are moved every time we run this script.
			    $tempAgents = $tempAgents | Get-Random -Count $agentDiff
			    $movableAgents += $tempAgents
		    }
	    } else {
		    $belowAverageMS += $scomMS
	    }
    }

    # At this point we have $movableAgents which contains all agents that has to be moved
    # to maintain an even spread among the management servers.
    # We also have $belowAverageMS that has all the management servers that currently
    # has too few agents at the moment.
    # We're going to parse the $belowAverageMS array and assign the $agentDiff number of
    # agents from $movableAgents to it. The agent and the MS will be added to a hashtable
    # for later processing as this will improve the speed.

    foreach ($scomMS in $belowAverageMS) {
	    $tempAgents = $scomAgents | where{$_.PrimaryManagementServerName -eq $scomMS.Name}
	    [int]$tempAgentCount = $tempAgents.Count
	    [int]$agentDiff = $averageAgents - $tempAgentCount
	    if ($agentDiff -gt 0) {
		    if ($movableAgents.Count -ge $agentDiff) {
			    # Selecting at random again because it's easy and pretty fail-safe.
			    $tempAgents = $movableAgents | Get-Random -Count $agentDiff
		    } else {
			    $tempAgents = $movableAgents
		    }
		    foreach($tempAgent in $tempAgents) {
			    # Looping through and removing the assigned agents from the $movableAgents array
			    $movableAgents = $movableAgents | where {$_.PrincipalName -ne $tempAgent.PrincipalName}
		    }
		    foreach ($scomAgent in $tempAgents) {
			    # Add the agent and PrimaryMS to the $agentSettings hashtable
			    $agentSettings.Add($scomAgent,$scomMS)
		    }
	    }
    }

    # We need to handle the scenario that one MS can have two or more agents surplus
    # (that is, $modAgents are >2) and all the rest of the management servers are
    # spot on "average" as this case is not caught by the above loop.
    # It is easily spotted as $movableAgents still is not empty or $null.
    while ($movableAgents.Count -gt 0) {
	    foreach ($scomMS in $belowAverageMS) {
		    $tempAgent = $movableAgents | Get-Random
		    $agentSettings.Add($tempAgent,$scomMS)
		    $movableAgents = $movableAgents | where {$_.PrincipalName -ne $tempAgent.PrincipalName}
		    if ($movableAgents.Count -lt 1) {
			    break
		    }
	    }
    }

    # Loop through the $agentSettings hashtable containing agent/primaryMS key/value pairs.
    # Use the primaryMS to get Fail-over MSs (all the rest), build the required <IList> and
    # run SetManagementServers() to execute.
    foreach($agentSetting in $agentSettings.GetEnumerator()) {
	    $scomAgent = $agentSetting.Key
	    $scomPrimaryMS = $agentSetting.Value
	    $scomFailOverMSs = @($scomMSs | where {$_.Name -ne $scomPrimaryMS.Name})
	    $scomMSList = New-Object 'Collections.Generic.List[Microsoft.EnterpriseManagement.Administration.ManagementServer]'
	    foreach ($scomFailOverMS in $scomFailOverMSs) {
		    $scomMSList.Add($scomFailOverMS)
	    }
        #Write-Output -InputObject "$($scomAgent.Name):`tPrimary MS: $($scomPrimaryMS.Name)`tFailoverMS: $($scomMSList.Name)"
	    $scomAgent.SetManagementServers($scomPrimaryMS,$scomMSList)
    }

    # Done!
}

function Main()
{
    $rps = Get-SCOMFailoverResourcePools -Prefix "Agent Fail-Over"
    foreach ($rp in $rps)
    {
        $mss = Get-SCOMMResourcePoolMembers -ResourcePool $rp
        if ($mss.Count -gt 0) {
            Update-SCOMAgentDistribution -ManagementServers $mss
        }
    }
}

# Execute!
Main