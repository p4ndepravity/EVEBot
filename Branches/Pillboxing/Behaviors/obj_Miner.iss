/*
	Miner Class

	Primary Miner hebavior module for EVEBot

	-- CyberTech

*/

objectdef obj_Miner
{
	variable string SVN_REVISION = "$Rev$"
	variable int Version

	variable time NextPulse
	variable int PulseIntervalInSeconds = 2

	variable index:entity LockedTargets
	variable iterator Target
	variable int TotalTrips = 0						/* Total Times we've had to transfer to hanger */
	variable time TripStartTime
	variable int PreviousTripSeconds = 0
	variable int TotalTripSeconds = 0
	variable int AverageTripSeconds = 0
	variable string CurrentState = "IDLE"
	variable bool CombatAbort = FALSE
	variable int SanityCheckCounter = 0
	variable bool SanityCheckAbort = FALSE
	variable float64 LastUsedCargoCapacity = 0

	; Are we running out of asteroids to target?
	variable bool ConcentrateFire = FALSE

	method Initialize()
	{
		BotModules:Insert["Miner"]

		This.TripStartTime:Set[${Time.Timestamp}]
		Event[EVENT_ONFRAME]:AttachAtom[This:Pulse]
		UI:UpdateConsole["obj_Miner: Initialized", LOG_MINOR]
	}

	method Shutdown()
	{
		Event[EVENT_ONFRAME]:DetachAtom[This:Pulse]
	}

	method Pulse()
	{
		if ${EVEBot.Paused}
		{
			return
		}

		if !${Config.Common.BotModeName.Equal[Miner]}
		{
			; There's no reason at all for the miner to check state if it's not a miner
			return
		}

	    if ${Time.Timestamp} >= ${This.NextPulse.Timestamp}
		{
			This:SetState[]
            SanityCheckCounter:Inc

    		This.NextPulse:Set[${Time.Timestamp}]
    		This.NextPulse.Second:Inc[${This.PulseIntervalInSeconds}]
    		This.NextPulse:Update
		}
	}

	function ProcessState()
	{
		if !${Config.Common.BotModeName.Equal[Miner]}
		{
			; There's no reason at all for the miner to check state if it's not a miner
			return
		}

		switch ${This.CurrentState}
		{
			case IDLE
				break
			case ABORT
				Call Station.Dock
				Call This.Abort_Check
				break
			case BASE
				call Cargo.TransferOreToHangar
				;call Station.CheckList
			    SanityCheckCounter:Set[0]
			    SanityCheckAbort:Set[FALSE]
			    LastUsedCargoCapacity:Set[0]
				call Station.Undock
				break
			case MINE
				call This.Mine
				break
			case HAUL
				UI:UpdateConsole["Hauling"]
				call Hauler.Haul
				break
			case DROPOFF
				switch ${Config.Miner.DeliveryLocationTypeName}
				{
					case Station
						; Gets info about the crystals currently loaded
						call Ship.SetActiveCrystals

						if ${EVE.Bookmark[${Config.Miner.DeliveryLocation}](exists)}
						{
							call Ship.WarpToBookMarkName "${Config.Miner.DeliveryLocation}"
						}
						else
						{
							call Station.Dock
						}
						break
					case Hangar Array
						call Ship.WarpToBookMarkName "${Config.Miner.DeliveryLocation}"
						call Cargo.TransferOreToCorpHangarArray
						break
					case Large Ship Assembly Array
						call Ship.WarpToBookMarkName "${Config.Miner.DeliveryLocation}"
						call Cargo.TransferOreToLargeShipAssemblyArray
						break
					case XLarge Ship Assembly Array
						call Ship.WarpToBookMarkName "${Config.Miner.DeliveryLocation}"
						call Cargo.TransferOreToXLargeShipAssemblyArray
						break
					case Jetcan
						UI:UpdateConsole["Warning: Cargo filled during jetcan mining, delays may occur"]
						call Cargo.TransferOreToJetCan
						This:NotifyHaulers[]
						break
					Default
						UI:UpdateConsole["ERROR: Delivery Location Type ${Config.Miner.DeliveryLocationTypeName} unknown"]
						EVEBot.ReturnToStation:Set[TRUE]
						break
				}
			    SanityCheckCounter:Set[0]
			    SanityCheckAbort:Set[FALSE]
			    LastUsedCargoCapacity:Set[0]
				break
			case RUNNING
				UI:UpdateConsole["Running Away"]
				call Station.Dock
				EVEBot.ReturnToStation:Set[TRUE]
				break
		}
	}

	method SetState()
	{
		/* TODO: CyberTech: Move this to the state machine, have it check for when the system is clear */
		if !${EVEBot.ReturnToStation} && \
			((${Config.Miner.StandingDetection} && ${Social.StandingDetection[${Config.Miner.LowestStanding}]}) || \
			!${Social.IsSafe})
		{
			EVEBot.ReturnToStation:Set[TRUE]
			UI:UpdateConsole["Warning: Low Standing player or system unsafe, docking"]
		}

		if ${Social.PossibleHostiles}
		{
			EVEBot.ReturnToStation:Set[TRUE]
			UI:UpdateConsole["Warning: Possible Hostiles on grid, docking"]
		}

		if ${Ship.IsPod}
		{
			UI:UpdateConsole["Warning: We're in a pod, running"]
			EVEBot.ReturnToStation:Set[TRUE]
			This.CurrentState:Set["ABORT"]
		}

		if ${EVEBot.ReturnToStation} && ${Me.InStation} == TRUE
		{
			This.CurrentState:Set["IDLE"]
			return
		}

		if ${EVEBot.ReturnToStation}
		{
			This.CurrentState:Set["ABORT"]
			return
		}

		if ${Me.InStation} == TRUE
		{
	  		This.CurrentState:Set["BASE"]
	  		return
		}

		if ${MyShip.UsedCargoCapacity} <= ${Config.Miner.CargoThreshold} && \
		    ${SanityCheckAbort} == FALSE
		{
		 	This.CurrentState:Set["MINE"]
			return
		}

	    if ${MyShip.UsedCargoCapacity} > ${Config.Miner.CargoThreshold} || \
    	    ${EVEBot.ReturnToStation}  || \
    	    ${SanityCheckAbort} == TRUE
		{
			This.CurrentState:Set["DROPOFF"]
			return
		}

		This.CurrentState:Set["Unknown"]
	}

	function Abort_Check()
	{
		call Config.Common.IncAbortCount
		; abort check, this will allow the bot to continue botting if it is a temp abort or something that can
		; if there is no abort type it will pause the script like before and wait...

		if ${This.CombatAbort}
			{
				UI:UpdateConsole["Warning: Paused. Combat type abort."]

				if ((${MyShip.ArmorPct} < ${Config.Combat.MinimumArmorPct}) && ${Ship.ArmorRepairUnits} == 0)
				{
					UI:UpdateConsole["Warning: Script paused due to Armor Precentage."]
					Script:Pause
				}

				; To.Do NEED TO ADD CHECK FOR HULL REPAIRER in SHIP OBJECT.
				if ((${MyShip.StructurePct} < 100))
				{
					UI:UpdateConsole["Warning: Aborted. Script paused due to Structure Percentage."]

					Script:Pause
				}

				if ${MyShip.ShieldPct} < 100
				{
					UI:UpdateConsole["Warning: Waiting for Shields to Regen."]
					while ${MyShip.ShieldPct} < 95
					{
						wait 20
					}
				}

				UI:UpdateConsole["Continuing"]
				EVEBot.ReturnToStation:Set[FALSE]
				This.CombatAbort:Set[FALSE]
				Return
			}

		UI:UpdateConsole["Warning: Aborted - Script Paused - Check Logs "]
		Script:Pause
	}

	; Enable defenses, launch drones
	function Prepare_Environment()
	{
		call Ship.OpenCargo
	}

	function Cleanup_Environment()
	{
		call Ship.Drones.ReturnAllToDroneBay
		;;;call Ship.CloseCargo
	}

	function Statslog()
	{
		variable string Hours = ${Math.Calc[(${Script.RunningTime}/1000/60/60)%60].Int.LeadingZeroes[2]}
		variable string Minutes = ${Math.Calc[(${Script.RunningTime}/1000/60)%60].Int.LeadingZeroes[2]}
		variable string Seconds = ${Math.Calc[(${Script.RunningTime}/1000)%60].Int.LeadingZeroes[2]}

		UI:UpdateStatStatus["Run ${This.TotalTrips} Done - Took ${ISXEVE.SecsToString[${This.PreviousTripSeconds}]}"]
		UI:UpdateStatStatus["Total Run Time: ${Hours}:${Minutes}:${Seconds} - Average Run Time: ${ISXEVE.SecsToString[${Math.Calc[${This.TotalTripSeconds}/${This.TotalTrips}]}]}"]
	}

	function Mine()
	{
		variable int TargetJammedCounter=0
		variable int BuddyCounter
		variable string buddyTest
		variable bool buddyOnline

		if ${Me.InStation} != FALSE
		{
			UI:UpdateConsole["DEBUG: obj_Miner.Mine called while zoning or while in station!"]
			return
		}

		This.TripStartTime:Set[${Time.Timestamp}]
		; Find an asteroid field, or stay at current one if we're near one.
		call Asteroids.MoveToField FALSE
		call This.Prepare_Environment
		call Asteroids.UpdateList

		variable int DroneCargoMin = ${Math.Calc[(${Ship.CargoMinimumFreeSpace}*1.4)]}
		variable int Counter = 0

		UI:UpdateConsole["Mining"]

		while ( !${EVEBot.ReturnToStation} && \
				${MyShip.UsedCargoCapacity} <= ${Config.Miner.CargoThreshold}	)
		{
			/* TODO: CyberTech: Move this to the state machine, have it check for when the system is clear */
			if (${Config.Miner.StandingDetection} && \
				${Social.StandingDetection[${Config.Miner.LowestStanding}]}) || \
				!${Social.IsSafe}
			{
				EVEBot.ReturnToStation:Set[TRUE]
				UI:UpdateConsole["Warning: Low Standing player or system unsafe, docking"]
			}

			if ${Ship.TotalMiningLasers} == 0
			{
				UI:UpdateConsole["Warning: No mining lasers detected, docking"]
				EVEBot.ReturnToStation:Set[TRUE]
				return
			}

			if ${Config.Combat.LaunchCombatDrones} && \
				${Ship.Drones.CombatDroneShortage}
			{
				/* TODO - This should pick up drones from station instead of just docking */
				UI:UpdateConsole["Warning: Drone shortage detected, docking"]
				EVEBot.ReturnToStation:Set[TRUE]
				return
			}

			if ${MyShip.UsedCargoCapacity} != ${LastUsedCargoCapacity}
			{
				;UI:UpdateConsole["DEBUG: ${MyShip.UsedCargoCapacity} != ${LastUsedCargoCapacity}"]
			    SanityCheckCounter:Set[0]
			    LastUsedCargoCapacity:Set[${MyShip.UsedCargoCapacity}]
			}

			if (!${Config.Miner.IceMining} && \
				${SanityCheckCounter} > MINER_SANITY_CHECK_INTERVAL)
			{
				UI:UpdateConsole["Warning: Cargo volume hasn't changed in a while, docking"]
				SanityCheckAbort:Set[TRUE]
				break
			}

			if ${Config.Combat.LaunchCombatDrones} && \
				${Ship.Drones.DronesInSpace} == 0 && \
				!${Ship.InWarp}
			{
				Ship.Drones:LaunchAll[]
			}

			if ${MyShip.MaxLockedTargets} == 0 && \
				 ${Ship.Drones.DronesInSpace} == 0
			{
				TargetJammedCounter:Inc
				if ${TargetJammedCounter} > 200
				{
					TargetJammedCounter:Set[0]
					UI:UpdateConsole["Warning: Ship target jammed, no drones available. Changing Belts"]
					call Asteroids.MoveToField TRUE
				}
			}
			else
			{
				TargetJammedCounter:Set[0]
			}

			if ${Social.PlayerInRange[${Config.Miner.AvoidPlayerRange}]}
			{
				UI:UpdateConsole["Avoiding player: Changing Belts"]
				call This.Cleanup_Environment
				call Asteroids.MoveToField TRUE
				call This.Prepare_Environment
			}

			if ${Config.Miner.DeliveryLocationTypeName.Equal[Jetcan]} && ${Ship.CargoHalfFull}
			{
				call Cargo.TransferOreToJetCan
				This:NotifyHaulers[]
				/* needed a wait here because it would try to move the same item more than once */
				wait 20
			}

			if (${MyShip.ArmorPct} < ${Config.Combat.MinimumArmorPct} || \
				${MyShip.ShieldPct} < ${Config.Combat.MinimumShieldPct})
			{
				/*
					TODO - CyberTech: This should be checked in a defensive class that runs regardless of which bot module is active
					instead of being checked in each module
				*/

				UI:UpdateConsole["Armor is at ${MyShip.ArmorPct}: ${MyShip.Armor}/${MyShip.MaxArmor}", LOG_CRITICAL]
				UI:UpdateConsole["Shield is at ${MyShip.ShieldPct}: ${MyShip.Shield}/${MyShip.MaxShield}", LOG_CRITICAL]
				UI:UpdateConsole["Miner aborting due to defensive status", LOG_CRITICAL]

				EVEBot.ReturnToStation:Set[TRUE]
				This.CombatAbort:Set[TRUE]
				return
			}

			if ${Ship.InWarp}
			{
				wait 10
				continue
			}

			if ${Ship.TotalActivatedMiningLasers} < ${Ship.TotalMiningLasers}
			{
				; We've got idle lasers, and available targets. Do something with them.
				while ${Me.TargetingCount} > 0
				{
				 	wait 10
				}

				Me:GetTargets[LockedTargets]
				LockedTargets:GetIterator[Target]
				if ${Target:First(exists)}
				do
				{
					if ${MyShip.UsedCargoCapacity} > ${Config.Miner.CargoThreshold}
					{
						break
					}

					if ${Target.Value.CategoryID} != ${Asteroids.AsteroidCategoryID}
					{
						continue
					}
					variable int64 TargetID
					TargetID:Set[${Target.Value.ID}]

					/* TODO: CyberTech - this concentrates fire fine if there's only 1 target, but if there's multiple targets it still prefers to distribute. Ice mining shouldn't distribute */
					if (${This.ConcentrateFire} || \
						${Config.Miner.IceMining} || \
						!${Config.Miner.DistributeLasers} || \
						!${Ship.IsMiningAsteroidID[${TargetID}]})
					{

						Target.Value:MakeActiveTarget
						while !${Target.Value.ID.Equal[${Me.ActiveTarget.ID}]}
						{
							wait 5
						}

						if ${MyShip.UsedCargoCapacity} > ${Config.Miner.CargoThreshold}
						{
							break
						}
						call Ship.Approach ${TargetID} ${Ship.OptimalMiningRange}
						call Ship.ActivateFreeMiningLaser

						if (${Ship.Drones.DronesInSpace} > 0 && \
							${Config.Miner.UseMiningDrones})
						{
							Ship.Drones:ActivateMiningDrones
						}
					}
				}
				while ${Target:Next(exists)}
			}

			if (!${Config.Miner.IceMining} || \
				(${Ship.TotalActivatedMiningLasers} == 0))
			{
				if ${Math.Calc[${Me.TargetCount} + ${Me.TargetingCount}]} < ${Ship.SafeMaxLockedTargets}
				{
					call Asteroids.TargetNext
					This.ConcentrateFire:Set[!${Return}]
					;echo DEBUG: Target Locking: ${Math.Calc[${Me.TargetCount} + ${Me.TargetingCount}].Int} out of ${Ship.SafeMaxLockedTargets} (Limited Asteroids: ${This.ConcentrateFire})
				}
				else
				{
					if ( ${Me.TargetCount} >= ${Ship.SafeMaxLockedTargets} && \
						 ${Ship.TotalMiningLasers} > ${Ship.SafeMaxLockedTargets} )
					{
						This.ConcentrateFire:Set[TRUE]
					}
				}
			}
			wait 10
		}

		if ${Config.Miner.BookMarkLastPosition}
		{
			Bookmarks:StoreLocation
		}
		call This.Cleanup_Environment
		This.TotalTrips:Inc
		This.PreviousTripSeconds:Set[${This.TripDuration}]
		This.TotalTripSeconds:Inc[${This.PreviousTripSeconds}]
		This.AverageTripSeconds:Set[${Math.Calc[${This.TotalTripSeconds}/${This.TotalTrips}]}]
		UI:UpdateConsole["Cargo Hold has reached threshold, returning"]
		call ChatIRC.Say "Cargo Hold has reached threshold"
		call This.Statslog

	}

	member:int TripDuration()
	{
		return ${Math.Calc64[${Time.Timestamp} - ${This.TripStartTime.Timestamp}]}
	}


	member:float VolumePerCycle(string AsteroidType)
	{

	}

	method NotifyHaulers()
	{
		/* notify hauler there is ore in space */
		variable string tempString
		tempString:Set["${Me.CharID},${Me.SolarSystemID},${Entity[GroupID = GROUP_ASTEROIDBELT].ID}"]
		relay all -event EVEBot_Miner_Full ${tempString}

		/* TO MANUALLY CALL A HAULER ENTER THIS IN THE CONSOLE
		 * relay all -event EVEBot_Miner_Full "${Me.CharID},${Me.SolarSystemID},${Entity[GroupID = 9].ID}"
		 */
	}

}
