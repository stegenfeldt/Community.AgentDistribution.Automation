# Community.AgentDistribution.Automation
Simple management pack to evenly distribute agents owned by servers within "Agent Fail-Over" resource pools.

## How to use

1. Import management pack
2. Create "Agent Fail-Over" resource pools for your Management and Gateway Servers
3. Chill

## How it works

The management pack contains a simple rule with a scheduler and a powershell write action.  
At 01:05 (at night) it will find all Resource Pools that starts with "Agent Fail-Over", collect management servers and gateway servers in them, one pool at the time, and all their agents.
It then looks for any imbalance in agent distribution and will try to randomly select (just) enough agents that are remotely manageable and re-distribute them between the management points. 

The script is written so that it makes sure the moved agents have the one primary management server and the rest in the pool as fail-over servers.  
It will also not attempt to move any agents if it would not make the distribution any more even.  
For examle; if the pool has two management servers where one has 20 agents and the other 21, nothing would improve if the extra agent on the other server was moved so the script will let it be.

That's it. 

## Credits

I wrote the bases for the script for an MSP back in the early days of SCOM 2012 and got the thumbs up on releasing it in a management pack if I honored their NDA and kept it Open Source.  
So thanks, anonymous MSP! 
