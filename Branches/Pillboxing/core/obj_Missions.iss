	/*
	Missions class

	Object to contain members related to missions.

	-- GliderPro

*/

objectdef obj_MissionCache
{
	variable string SVN_REVISION = "$Rev$"
	variable int Version

	variable string CONFIG_FILE = "${Script.CurrentDirectory}/Config/${Me.Name} Mission Cache.xml"
	variable string SET_NAME = "Missions"

	variable index:entity entityIndex
	variable iterator     entityIterator
	method Initialize()
	{
		LavishSettings[MissionCache]:Clear
		LavishSettings:AddSet[MissionCache]
		LavishSettings[MissionCache]:AddSet[${This.SET_NAME}]
		LavishSettings[MissionCache]:Import[${This.CONFIG_FILE}]
		UI:UpdateConsole["obj_MissionCache: Initialized", LOG_MINOR]
	}
	method Shutdown()
	{
		LavishSettings[MissionCache]:Export[${This.CONFIG_FILE}]
		LavishSettings[MissionCache]:Clear
	}

	member:settingsetref MissionsRef()
	{
		return ${LavishSettings[MissionCache].FindSet[${This.SET_NAME}]}
	}

	member:settingsetref MissionRef(int agentID)
	{
		return ${This.MissionsRef.FindSet[${agentID}]}
	}

	method AddMission(int agentID, string name)
	{
		This.MissionsRef:AddSet[${agentID}]
		This.MissionRef[${agentID}]:AddSetting[Name,"${name}"]
	}

	member:int FactionID(int agentID)
	{
		return ${This.MissionRef[${agentID}].FindSetting[FactionID,0]}
	}

	method SetFactionID(int agentID, int factionID)
	{
		if !${This.MissionsRef.FindSet[${agentID}](exists)}
		{
			This.MissionsRef:AddSet[${agentID}]
		}

		This.MissionRef[${agentID}]:AddSetting[FactionID,${factionID}]
	}

	member:int TypeID(int agentID)
	{
		return ${This.MissionRef[${agentID}].FindSetting[TypeID,0]}
	}
	member:string Name(int agentID)
	{
		return ${This.MissionRef[${agentID}].FindSetting[Name,0]}
	}

	method SetTypeID(int agentID, int typeID)
	{
		if !${This.MissionsRef.FindSet[${agentID}](exists)}
		{
			This.MissionsRef:AddSet[${agentID}]
		}

		This.MissionRef[${agentID}]:AddSetting[TypeID,${typeID}]
	}

	member:float Volume(int agentID)
	{
		return ${This.MissionRef[${agentID}].FindSetting[Volume,0]}
	}

	method SetVolume(int agentID, float volume)
	{
		if !${This.MissionsRef.FindSet[${agentID}](exists)}
		{
			This.MissionsRef:AddSet[${agentID}]
		}

		This.MissionRef[${agentID}]:AddSetting[Volume,${volume}]
	}

	member:bool LowSec(int agentID)
	{
		return ${This.MissionRef[${agentID}].FindSetting[LowSec,FALSE]}
	}

	method SetLowSec(int agentID, bool isLowSec)
	{
		if !${This.MissionsRef.FindSet[${agentID}](exists)}
		{
			This.MissionsRef:AddSet[${agentID}]
		}

		This.MissionRef[${agentID}]:AddSetting[LowSec,${isLowSec}]
	}
}

;objectdef obj_MissionDatabase
;{
;	variable string SVN_REVISION = "$Rev$"
;	variable int Version
;
;	variable string CONFIG_FILE = "${BaseConfig.CONFIG_PATH}/Mission Database.xml"
;	variable string SET_NAME = "Mission Database"
;
;	method Initialize()
;	{
;		if ${LavishSettings[${This.SET_NAME}](exists)}
;		{
;			LavishSettings[${This.SET_NAME}]:Clear
;		}
;		LavishSettings:Import[${CONFIG_FILE}]
;		LavishSettings[${This.SET_NAME}]:GetSettingIterator[This.agentIterator]
;     This:DumpDatabase
;	UI:UpdateConsole["obj_MissionDatabase: Initialized", LOG_MINOR]
;	}
;
;   method DumpDatabase()
;   {
;
;   }
;
;}

objectdef obj_Missions
{
	variable string SVN_REVISION = "$Rev$"
	variable int Version

	variable obj_MissionCache MissionCache
;   variable obj_MissionDatabase MissionDatabase
	variable obj_Combat Combat
	variable int RoomCounter
	variable bool bSalvaging = TRUE
	variable bool bWait
	variable int MissionTimer
	variable uint LootEntityQuery = ${LavishScript.CreateQuery[GroupID = "12" || Name =- "Transport" || GroupID = "306" || Name = "Rolette Residence" || Name = "Science Vessel Wreck"]}
	variable uint LootKeyQuery = ${LavishScript.CreateQuery[GroupID = "12" || Name =- "Officer"]}
	variable collection:int Keys
	variable collection:int MissionsToWait
	method Initialize()
	{
		UI:UpdateConsole["obj_Missions: Initialized", LOG_MINOR]
		This.Combat:Initialize
		Keys:Set["Guristas Extravaganza", 17206]
		Keys:Set["Angel Extravaganza", 17192]
		Keys:Set["Dread Pirate Scarlet", 2076]
		Keys:Set["Illegal Activity (2 of 3)",24030]
		MissionsToWait:Set["Illegal Activity (1 of 3)", 50]
		MissionsToWait:Set["Attack of the Drones",60]
		;; set the combat "mode"
		LavishScript:RegisterEvent[WHERE]
		Event[WHERE]:AttachAtom[This:Where]
		This.Combat:SetMode["AGGRESSIVE"]
	}

	method Shutdown()
	{
	}
	method Where(int64 ID)
	{
		if ${Me.ID} == ${ID}
		{
			if !${Me.InSpace} && ((${This.Combat.CurrentState.Equal["FLEE"]} || ${This.Combat.CurrentState.Equal["RESTOCK"]}) && !${This.AtHomeBase})
			{
				relay all Event[HERE]:Execute["0"]
			}
			else
			{
				This:RelayBookMarks
			}
		}
	}

	function RunMission()
	{
		variable index:agentmission amIndex
		variable iterator amIterator

		EVE:GetAgentMissions[amIndex]
		amIndex:GetIterator[amIterator]

		UI:UpdateConsole["obj_Missions: DEBUG: amIndex.Used = ${amIndex.Used}"]
		if ${amIterator:First(exists)}
		{
			do
			{
					UI:UpdateConsole["obj_Missions: DEBUG: amIterator.Value.AgentID = ${amIterator.Value.AgentID}"]
					UI:UpdateConsole["obj_Missions: DEBUG: amIterator.Value.State = ${amIterator.Value.State}"]
					UI:UpdateConsole["obj_Missions: DEBUG: amIterator.Value.Type = ${amIterator.Value.Type}"]
					if ${amIterator.Value.State} == 2 && ${amIterator.Value.AgentID} == ${Agents.AgentID}
					{
						call Agents.MissionDetails	
						if ${amIterator.Value.Type.Find[Courier](exists)}
						{
							call This.RunCourierMission ${amIterator.Value.AgentID}
						}
						elseif ${amIterator.Value.Type.Find[Trade](exists)}
						{
							call This.RunTradeMission ${amIterator.Value.AgentID}
						}
						elseif ${amIterator.Value.Type.Find[Mining](exists)}
						{
							call This.RunMiningMission ${amIterator.Value.AgentID}
						}
						elseif ${amIterator.Value.Type.Find[Encounter](exists)}
						{
							call This.RunCombatMission ${amIterator.Value.AgentID}
						}
						else
						{
							UI:UpdateConsole["obj_Missions: ERROR!  Unknown mission type!"]
							Script:Pause
						}
					}
			}
			while ${amIterator:Next(exists)}
		}
	}

method MoveOn()
{
	bWait:Set[FALSE]
	UI:UpdateConsole["All clear received from salvager > moving on!"]
}

function RunCourierMission(int agentID)
	{
		variable int        QuantityRequired
		variable string     itemName
		variable float      itemVolume
		variable bool       haveCargo = FALSE
		variable bool       allDone = FALSE
		variable index:item CargoIndex
		variable iterator   CargoIterator
		variable index:item HangItems
		variable iterator Items
		variable int        TypeID
		variable int        ItemQuantity

		call Cargo.CloseHolds
		call Cargo.OpenHolds

		Agents:SetActiveAgent[${Agent[id, ${agentID}].Name}]

		if ${This.MissionCache.Volume[${agentID}]} == 0
		{
			call Agents.MissionDetails
		}

		if ${This.MissionCache.Volume[${agentID}]} > ${Config.Missioneer.SmallHaulerLimit}
		{
			call Ship.ActivateShip "${Config.Missioneer.LargeHauler}"
		}
		else
		{
			call Ship.ActivateShip "${Config.Missioneer.SmallHauler}"
		}

		itemName:Set[${EVEDB_Items.Name[${This.MissionCache.TypeID[${agentID}]}]}]
		itemVolume:Set[${EVEDB_Items.Volume[${itemName}]}]
		if ${itemVolume} > 0
		{
			UI:UpdateConsole["DEBUG: RunCourierMission: ${This.MissionCache.TypeID[${agentID}]}:${itemName} has volume ${itemVolume}."]
			QuantityRequired:Set[${Math.Calc[${This.MissionCache.Volume[${agentID}]}/${itemVolume}]}]
		}
		else
		{
			UI:UpdateConsole["DEBUG: RunCourierMission: ${This.MissionCache.TypeID[${agentID}]}: Item not found!  Assuming one unit to move."]
			QuantityRequired:Set[1]
		}

		do
		{
			Cargo:FindShipCargoByType[${This.MissionCache.TypeID[${agentID}]}]
			if ${Cargo.CargoToTransferCount} == 0
			{
				UI:UpdateConsole["obj_Missions: MoveToPickup"]
				call Agents.MoveToPickup
				UI:UpdateConsole["obj_Missions: TransferCargoToShip"]
				EVE:Execute[OpenHangarFloor]
				wait 50
				;call Cargo.TransferHangarItemToShip ${This.MissionCache.TypeID[${agentID}]}
				;allDone:Set[${Cargo.LastTransferComplete}]
				Me.Station:GetHangarItems[HangItems]
				HangItems:GetIterator[Items]
				if ${Items:First(exists)}
				{
					do
					{
						if ${Items.Value.TypeID} == ${This.MissionCache.TypeID[${Agents.AgentID}]}
						{
							UI:UpdateConsole["Found '${Items.Value.Name}', transferring to ship."]
							Items.Value:MoveTo[${MyShip.ID},CargoHold]
						}
					}
					while ${Items:Next(exists)}
				}
			}

			UI:UpdateConsole["obj_Missions: MoveToDropOff"]
			call Agents.MoveToDropOff
			wait 50

			call Cargo.CloseHolds
			call Cargo.OpenHolds

			UI:UpdateConsole["DEBUG: RunCourierMission: Checking ship's cargohold for ${QuantityRequired} units of ${itemName}."]
			MyShip:GetCargo[CargoIndex]
			CargoIndex:GetIterator[CargoIterator]
			if ${CargoIterator:First(exists)}
			{
				do
				{
					TypeID:Set[${CargoIterator.Value.TypeID}]
					ItemQuantity:Set[${CargoIterator.Value.Quantity}]
					UI:UpdateConsole["DEBUG: RunCourierMission: Ship's Cargo: ${ItemQuantity} units of ${CargoIterator.Value.Name}(${TypeID})."]

					if (${TypeID} == ${This.MissionCache.TypeID[${agentID}]}) && \
					   (${ItemQuantity} >= ${QuantityRequired})
					{
						UI:UpdateConsole["DEBUG: RunCourierMission: Found required items in ship's cargohold."]
						haveCargo:Set[TRUE]
						break
					}	
				}
				while ${CargoIterator:Next(exists)}
			}

			if ${haveCargo} == TRUE
			{
				break
			}

			call Cargo.TransferItemTypeToHangar ${This.MissionCache.TypeID[${agentID}]}
			wait 50

			if ${Station.Docked}
			{
				UI:UpdateConsole["DEBUG: RunCourierMission: Checking station hangar for ${QuantityRequired} units of ${itemName}."]
				Me:GetHangarItems[CargoIndex]
				CargoIndex:GetIterator[CargoIterator]

				if ${CargoIterator:First(exists)}
				{
					do
					{
						TypeID:Set[${CargoIterator.Value.TypeID}]
						ItemQuantity:Set[${CargoIterator.Value.Quantity}]
						UI:UpdateConsole["DEBUG: RunCourierMission: Station Hangar: ${ItemQuantity} units of ${CargoIterator.Value.Name}(${TypeID})."]

						if (${TypeID} == ${This.MissionCache.TypeID[${agentID}]}) && \
						   (${ItemQuantity} >= ${QuantityRequired})
						{
							UI:UpdateConsole["DEBUG: RunCourierMission: Found required items in station hangar."]
							allDone:Set[TRUE]
							break
						}
					}
					while ${CargoIterator:Next(exists)}
				}
			}
		}
		while !${allDone}

		UI:UpdateConsole["obj_Missions: TurnInMission"]
		call Agents.TurnInMission
	}

	function RunTradeMission(int agentID)
	{
		variable int        QuantityRequired
		variable string     itemName
		variable bool       haveCargo = FALSE
		variable index:item CargoIndex
		variable iterator   CargoIterator
		variable int        TypeID
		variable int        ItemQuantity

		Agents:SetActiveAgent[${Agent[id,${agentID}]}]

		itemName:Set[${EVEDB_Items.Name[${This.MissionCache.TypeID[${agentID}]}]}]
		QuantityRequired:Set[${Math.Calc[${This.MissionCache.Volume[${agentID}]}/${EVEDB_Items.Volume[${itemName}]}]}]

		call Cargo.CloseHolds
		call Cargo.OpenHolds

		;;; Check the cargohold of your ship
		MyShip:GetCargo[CargoIndex]
		CargoIndex:GetIterator[CargoIterator]
		if ${CargoIterator:First(exists)}
		{
			do
			{
				TypeID:Set[${CargoIterator.Value.TypeID}]
				ItemQuantity:Set[${CargoIterator.Value.Quantity}]
				UI:UpdateConsole["DEBUG: RunTradeMission: Ship's Cargo: ${ItemQuantity} units of ${CargoIterator.Value.Name}(${TypeID})."]

				if (${TypeID} == ${This.MissionCache.TypeID[${agentID}]}) && \
				   (${ItemQuantity} >= ${QuantityRequired})
				{
					UI:UpdateConsole["DEBUG: RunTradeMission: Found required items in ship's cargohold."]
					haveCargo:Set[TRUE]
				}
			}
			while ${CargoIterator:Next(exists)}
		}

		if ${This.MissionCache.Volume[${agentID}]} > ${Config.Missioneer.SmallHaulerLimit}
		{
			call Ship.ActivateShip "${Config.Missioneer.LargeHauler}"
		}
		else
		{
			call Ship.ActivateShip "${Config.Missioneer.SmallHauler}"
		}

		;;; Check the hangar of the current station
		if ${haveCargo} == FALSE && ${Station.Docked}
		{
			Me:GetHangarItems[CargoIndex]
			CargoIndex:GetIterator[CargoIterator]

			if ${CargoIterator:First(exists)}
			{
				do
				{
					TypeID:Set[${CargoIterator.Value.TypeID}]
					ItemQuantity:Set[${CargoIterator.Value.Quantity}]
					UI:UpdateConsole["DEBUG: RunTradeMission: Station Hangar: ${ItemQuantity} units of ${CargoIterator.Value.Name}(${TypeID})."]

					if (${TypeID} == ${This.MissionCache.TypeID[${agentID}]}) && \
					   (${ItemQuantity} >= ${QuantityRequired})
					{
						UI:UpdateConsole["DEBUG: RunTradeMission: Found required items in station hangar."]
						if ${Agents.InAgentStation} == FALSE
						{
							call Cargo.TransferHangarItemToShip ${This.MissionCache.TypeID[${agentID}]}
						}
						haveCargo:Set[TRUE]
					}
				}
				while ${CargoIterator:Next(exists)}
			}
		}

		;;;  Try to buy the item
		if ${haveCargo} == FALSE
		{
			if ${Station.Docked}
			{
				call Station.Undock
			}

			call Market.GetMarketOrders ${This.MissionCache.TypeID[${agentID}]}
			call Market.FindBestWeightedSellOrder ${Config.Missioneer.AvoidLowSec} ${quantity}
			call Ship.TravelToSystem ${Market.BestSellOrderSystem}
			call Station.DockAtStation ${Market.BestSellOrderStation}
			call Market.PurchaseItem ${This.MissionCache.TypeID[${agentID}]} ${quantity}

			call Cargo.TransferHangarItemToShip ${This.MissionCache.TypeID[${agentID}]}

			if ${Cargo.LastTransferComplete} == FALSE
			{
				UI:UpdateConsole["obj_Missions: ERROR: Couldn't carry all the trade goods!  Pasuing script!!"]
				Script:Pause
			}
		}

		;;;UI:UpdateConsole["obj_Missions: MoveTo Agent"]
		call Agents.MoveTo
		wait 50
		;;;call Cargo.TransferItemTypeToHangar ${This.MissionCache.TypeID[${agentID}]}
		;;;wait 50

		UI:UpdateConsole["obj_Missions: TurnInMission"]
		call Agents.TurnInMission
	}

	function RunMiningMission(int agentID)
	{
		UI:UpdateConsole["obj_Missions: ERROR!  Mining missions are not supported!"]
		Script:Pause
	}

	function RunCombatMission(int agentID)
	{	
		if !${Combat.HaveMissionAmmo} && ${Config.Combat.RestockAmmo}
		{
			call Combat.RestockAmmo
		}
		call This.GetMissionKey
		UI:UpdateConsole["Starting combat mission now."]
		call ChatIRC.Say "${Me.Name}: Starting new mission. Name = ${This.MissionCache.Name[${Agents.AgentID}]}"
		;call Ship.ActivateShip "${Config.Missioneer.CombatShip}"
		;wait 10
		call This.WarpToEncounter ${Agents.AgentID}
		call Ship.SwapAmmo
		wait 100
		while ${Me.AutoPilotOn}
		{
			UI:UpdateConsole["Activating autopilot."]
		}
		call This.RunCombatMish
		call This.WarpToHomeBase ${Agents.AgentID}
		wait 50
		call Agents.TurnInMission
	}

	function RunCombatMish()
	{
		UI:UpdateConsole["obj_Missions: DEBUG: Calling mission start"]
		MissionTimer:Set[${Script.RunningTime}]
		variable bool missionComplete = FALSE
		variable time breakTime = ${Time.Timestamp}
		variable int Counter = 1
		variable index:entity Ents
		variable int64 GateToUse		
		variable bool SET
		RoomCounter:Set[1]
		; wait up to 15 seconds for spawns to appear
		breakTime:Set[${Time.Timestamp}]
		;START OF LOOP THAT DOESN'T TERMINATE UNTIL THERE ARE NO GATES
		do
		{
			if ${MissionsToWait.Element[${This.MissionCache.Name[${Agents.AgentID}]}]} > 0
			{
				breakTime.Second:Inc[${MissionsToWait.Element[${This.MissionCache.Name[${Agents.AgentID}]}]}]
			}
			else
			{
				if !${This.BookmarkExists}
				{
					breakTime.Second:Inc[15]		
				}
			}
			breakTime:Update
			while !${Targets.TargetNPCs}
			{
				UI:UpdateConsole["No rats found, waiting on spawn."]
			   if ${Time.Timestamp} >= ${breakTime.Timestamp}
			   {
			   		UI:UpdateConsole["No rats found in timeout time, moving on."]
					break    
			   }
			   wait 50
			}
			;START OF LOOP THAT DOESN'T END UNTIL THERE ARE NO RATS
			do 
			{
				while ${breakTime.Timestamp} > ${Time.Timestamp} && !${This.BookmarkExists}
				{
					if ${Targets.TargetNPCs}
					{
						break
					}
					wait 50
					UI:UpdateConsole["Waiting on spawns"]
				}
			   if ${This.Combat.CurrentState.Equal["FIGHT"]} && ${Me.TargetCount} > 0
			   {
					if ${Targets.ToTarget.Used} == 0
					{
						call This.Combat.ProcessState
					}
					elseif ${Targets.ToTarget.Used} > 0 && ${Entity[${Targets.ToTarget[1]}].IsActiveTarget}
					{
						call This.Combat.ProcessState
					}
			   }
			   else
			   {
				   	if !${Combat.CurrentState.Equal["RESTOCK"]} && ${Me.TargetCount} > 0
				   	{
						Combat:SetState
						UI:UpdateConsole["Setting state on combat!"]
					}
			   }
				if ${This.Combat.CurrentState.Equal["FLEE"]} || ${This.Combat.CurrentState.Equal["RESTOCK"]}
				{
					UI:UpdateConsole["Done Fleeing, returning to mission."]
					call This.WarpToEncounter ${Agents.AgentID}
					RoomCounter:Set[1]
				}
				wait 30
			}
			while ${Targets.TargetNPCs}
			if ${This.GatePresent} && (${RoomCounter} < 6 || ${This.HaveMissionKey})
			{
				if ${Entity["TypeID = TYPE_ACCELERATION_GATE"].Name.Equal["Gate To The Serpentis Base"]}
				{
					GateToUse:Set[${Entity["TypeID = TYPE_ACCELERATION_GATE && Distance > ${Entity["TypeID = TYPE_ACCELERATION_GATE"].Distance}"].ID}]
				}
				else
				{
					GateToUse:Set[${Entity["TypeID = TYPE_ACCELERATION_GATE"].ID}]
				}
				EVE:Execute[CmdDronesReturnToBay]
				if ${Config.Missioneer.SalvageModeName.Equal["Relay"]}
				{
					if !${This.BookmarkExists}
					{
						if !${Entity["GroupID = 186 || GroupID = 12"](exists)}
						{
							UI:UpdateConsole["No salvageable entities found, not bookmarking anything."]
						}
						else
						{
							UI:UpdateConsole["Bookmarking closest entitity now."]
							Entity["GroupID = 186 || GroupID = 12"]:CreateBookmark["Salvage","S","Corporation Locations"]
						}	
					}
					else
					{
						UI:UpdateConsole["We already have a bookmark for this room, moving on."]
					}	
				}			
				UI:UpdateConsole["No Entities found, moving to next room. ${Entity[${GateToUse}].Name} found."]
				call Ship.Approach ${GateToUse} 2500
				call Ship.WarpPrepare
				/* activate gate and go to next room */
			   	UI:UpdateConsole["Activating Acceleration Gate..."]
			   	while ${Me.ToEntity.Mode} != 3
			   	{
			   		Entity[${GateToUse}]:Activate
					wait 10			   		
			   	}
				RoomCounter:Inc
				call Ship.WarpWait
				UI:UpdateConsole["Room Number: ${RoomCounter}"]
				call ChatIRC.Say "${Me.Name}: Moving rooms, now entering ${RoomCounter}"
				breakTime:Set[${Time.Timestamp}]
				breakTime.Second:Inc[15]
				breakTime:Update
			}
		}
		while (${This.GatePresent} && (${RoomCounter} < 6 || ${This.HaveMissionKey}) || ${Me.ToEntity.Mode} == 3 || ${Targets.TargetNPCs})
		;If we need to loot something it will happen now, since this code should only do what I want it to
		echo ${This.MissionCache.Volume[${Agents.AgentID}]} 
		if ${This.MissionCache.Volume[${Agents.AgentID}]} > 0 && !${This.HaveMishItem}
			; this check should be incorporated into if statement
			{
				EVE:QueryEntities[Ents, ${LootEntityQuery}]
				variable iterator Ent
				variable index:item   Items
				variable iterator   Item
				UI:UpdateConsole["Found ${Ents.Used} entities in total to loot."]
				Ents:GetIterator[Ent]
				UI:UpdateConsole["Looting ${This.MissionCache.TypeID[${Agents.AgentID}]}"]
				if ${Ent:First(exists)}
				{
					do
					{
						if !${Ship.Approaching.Equal[${Ent.Value.ID}]}
						{
							call Ship.Approach ${Ent.Value.ID} 1000
						}
						UI:UpdateConsole["Opening ${Ent.Value.Name} to loot mission item."]
						Ent.Value:Open
						wait 10
						call Ship.OpenCargo
						wait 10
						Ent.Value:GetCargo[Items]
						Items:GetIterator[Item]
						if ${Item:First(exists)}
						{
							if ${Targets.TargetNPCs}
							{
								call This.RunCombatMish
								break
							}
							do
							{
								if ${Item.Value.TypeID} == ${This.MissionCache.TypeID[${Agents.AgentID}]}
								{
									UI:UpdateConsole["Found mission item: Looting!"]
									Item.Value:MoveTo[${MyShip.ID},CargoHold]
									wait 10
									breakTime:Set[${Time.Timestamp}]
									breakTime.Second:Inc[15]
									breakTime:Update
									do 
									{
										UI:UpdateConsole["Waiting on spawns."]
										wait 500
									}
									while !${Targets.TargetNPCs} && ${Time.Timestamp} < ${breakTime.Timestamp}
									if ${Config.Missioneer.SalvageModeName.Equal["Relay"]}
									{
										if !${This.BookmarkExists}
										{
											UI:UpdateConsole["Bookmarking closest entity now."]
											Entity["GroupID = 186"]:CreateBookmark["Salvage","S","Corporation Locations"]
										}
										else
										{
											UI:UpdateConsole["We already have a bookmark for this room, not doing anything."]
										}			
									}
								}
								else
								{
									echo "DERP ${Item.Value.TypeID}"
								}
								if ${This.HaveMishItem}
								{
									break
								}
							}
							while ${Item:Next(exists)}
						}
					}
					while ${Ent:Next(exists)}
					if !${This.HaveMishItem}
					{
						UI:UpdateConsole["We still don't have mission item, something is very wrong. ERROR. ABORT ABORT ABORT."]
					}       
				}
				else
				{
					UI:UpdateConsole["Nothing found to loot for item mish! Pausing Script."]
					Script:Pause
				}
			}
			if !${This.BookmarkExists} && ${Config.Missioneer.SalvageModeName.Equal["Relay"]}
			{
				UI:UpdateConsole["Bookmarking closest entity now."]
				Entity["GroupID = 186 || GroupID = 12"]:CreateBookmark["Salvage","S","Corporation Locations"]
			}			
			else
			{
				UI:UpdateConsole["We already have a bookmark for this room, going on!"]
			}
			MissionTimer:Set[${Math.Calc[${Script.RunningTime}-${MissionTimer}]}]
			MissionTimer:Set[${Math.Calc[${MissionTimer}/60000]}]
			UI:UpdateConsole["Finished mission, heading to active agent for new one. This mission took ${MissionTimer} minutes and ${Math.Calc[${MissionTimer}%60]} seconds. :O"]
			call ChatIRC.Say "Finished mission, heading to active agent for new one. This mission took ${MissionTimer} minutes and ${Math.Calc[${MissionTimer}%60]} seconds. :O"
			;I should probably do some actual logging and stuff, as well as assigning this to a cleaner algrothim, however for the time being I'll fix this if it doesn't work and leave it as is.
			
	}
	member:bool HaveMissionKey()
	{
		variable index:item Items
		variable uint querie = ${LavishScript.CreateQuery[TypeID != "${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]}"]}
		if ${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]} > 0
		{
			MyShip:GetCargo[Items]
			if ${Items.Used} == 0
			{
				UI:UpdateConsole["HaveMissionKey: No items found in cargo, we have to return false"]
				return FALSE
			}
			Items:RemoveByQuery[${querie}]
			Items:Collapse
			if ${Items.Used} > 0
			{
				UI:UpdateConsole["We have key in cargo, time for a spot of tea old chap."]
				return TRUE
			}
			else
			{
				return FALSE
			}
		}
		else
		{
			return TRUE
		}
	}

	function GetMissionKey()
	{
		variable index:item Items
		variable iterator Item
		echo "${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]}"
		variable uint querie = ${LavishScript.CreateQuery[TypeID != "${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]}"]}
		
		if ${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]} > 0
		{
			MyShip:GetCargo[Items]
			Items:RemoveByQuery[${querie}]
			Items:Collapse
			if ${Items.Used} > 0
			{
				UI:UpdateConsole["We have key in cargo already, time for a spot of tea old chap."]
			}
			else
			{
				if !${Me.InSpace}
				{
					UI:UpdateConsole["Not in space, and the key wasn't found in cargo, so I shall look in the hangar old bean."]
					Items:Clear
					Me.Station:GetHangarItems[Items]
					UI:UpdateConsole["Found ${Items.Used} items in hangar."]
					Items:RemoveByQuery[${querie}]
					Items:Collapse
					if ${Items.Used} > 0
					{
						UI:UpdateConsole["Found ${Items[1].Name} in hangar, moving to cargo"]
						Items[1]:MoveTo[${MyShip.ID},CargoHold]
					}
					else
					{
						UI:UpdateConsole["No key found in hangar, moving on!"]
					}
				}
				else
				{
					variable index:entity ThingsToLoot
					variable iterator itty
					EVE:QueryEntities[ThingsToLoot,${LootKeyQuery}]
					if ${ThingsToLoot.Used} > 0
					{
						ThingsToLoot:GetIterator[itty]
						itty:First
						do
						{
							if !${Me.ToEntity.Approaching.ID.Equal[${itty.Value.ID}]}
							{
								itty.Value:Approach
								while ${itty.Value.Distance} > 2500
								{
									wait 100
								}
								itty.Value:OpenCargo
								wait 10
								call Ship.OpenCargo
								wait 10
								itty.Value:GetCargo[Items]
								Items:GetIterator[Item]
								if ${Item:First(exists)}
								{
									do
									{
										if ${Item.Value.TypeID.Equal[${Keys.Element[${This.MissionCache.Name[${Agents.AgentID}]}]}]}
										{
											UI:UpdateConsole["Looting ${Item.Value.Name} because it's a mission key."]
											Item.Value:MoveTo[MyShip,CargoHold]
											break
										}
									}
									while ${Item:Next(exists)}
								}
							}
						}
						while ${itty:Next(exists)}
					}
				}
			}
		}
		else
		{
			UI:UpdateConsole["No key needed old chap, no big deal. ${This.MissionCache.Name[${Agents.AgentID}]}"]
		}
	}


   member:bool GatePresent()
   {
   		if ${Entity["TypeID = TYPE_ACCELERATION_GATE"](exists)}
   		{
   			if ${Entity["TypeID = TYPE_ACCELERATION_GATE"].Name.Equal["Gate to the Warzone"]}
   			{
	  			return FALSE
	  		}
	  		else
	  		{
	  			return TRUE
	  		}
	  }
   }

	function WarpToEncounter(int agentID)
	{
		variable index:agentmission amIndex
		variable index:bookmark mbIndex
		variable iterator amIterator
		variable iterator mbIterator

		EVE:GetAgentMissions[amIndex]
		amIndex:GetIterator[amIterator]

		if ${amIterator:First(exists)}
		{
			do
			{
				if ${amIterator.Value.AgentID} == ${Agents.AgentID}
				{
					amIterator.Value:GetBookmarks[mbIndex]
					mbIndex:GetIterator[mbIterator]

					if ${mbIterator:First(exists)}
					{
						do
						{
							if ${mbIterator.Value.LocationType.Equal["dungeon"]}
							{
								if ${mbIterator.Value.Distance} > 100000000 || !${mbIterator.Value.Distance(exists)}
								{
									while ${mbIterator.Value.Distance} > 100000000 || !${mbIterator.Value.Distance(exists)}
									{
										if ${mbIterator.Value.ID} <= 0
										{
											UI:UpdateConsole["NULL Bookmark found, calling WarpToEncounter again and then breaking this version"]
											call This.WarpToEncounter ${Agents.AgentID}
											return
										}
										if ${mbIterator.Value.ID} > 0
										{
											call Ship.WarpToBookMark ${mbIterator.Value.ID}
										}
									}
									return
								}
								else
								{
									UI:UpdateConsole["We're probably already at mission, not warping this time old chap."]
								}
							}
						}
						while ${mbIterator:Next(exists)}
					}
				}
			}
			while ${amIterator:Next(exists)}
		}
	}

	member:bool BookmarkExists()
	{
		variable index:bookmark BookmarksForMeToPissOn
		variable iterator BookmarkIter
		EVE:GetBookmarks[BookmarksForMeToPissOn]
		BookmarksForMeToPissOn:RemoveByQuery[${LavishScript.CreateQuery[OwnerID != "${Me.Corp.ID}"]}]
		;UI:UpdateConsole["BookmarkExists: Found ${BookmarksForMeToPissOn.Used} corp bookmarks."]
		BookmarksForMeToPissOn:Collapse
		BookmarksForMeToPissOn:GetIterator[BookmarkIter]
		if ${BookmarkIter:First(exists)}
		{
			;UI:UpdateConsole["Corp Bookmark found, name is ${BookmarkIter.Value.Label}"]
			do
			{
				if ${BookmarkIter.Value.Distance} < 500000 && ${BookmarkIter.Value.Distance} > 0
				{
					return TRUE
				}
				else
				{
					;UI:UpdateConsole["Bookmark found, name ${BookmarkIter.Value.Label}, Distance ${BookmarkIter.Value.Distance}"]
				}
			}
			while ${BookmarkIter:Next(exists)}
		}
		return FALSE
	}

	method RelayBookMarks()
	{
		variable index:bookmark BookmarksForMeToPissOn
		variable string BM
		variable iterator BookmarkIter
		EVE:GetBookmarks[BookmarksForMeToPissOn]
		BookmarksForMeToPissOn:Collapse
		BookmarksForMeToPissOn:RemoveByQuery[${LavishScript.CreateQuery[OwnerID != "${Me.Corp.ID}" || CreatorID != "${Me.ID}" || (Distance < "200000000" && SolarSystemID = "${Me.SolarSystemID}")]}]
		BookmarksForMeToPissOn:Collapse
		UI:UpdateConsole["RelayBookMarks: Found ${BookmarksForMeToPissOn.Used} bookmarks after query"]
		BookmarksForMeToPissOn:GetIterator[BookmarkIter]
		if ${BookmarkIter:First(exists)}
		{
			UI:UpdateConsole["Found BM at distance ${BookmarkIter.Value.Distance}, Name - ${BookmarkIter.Value.Label}"]
			BM:Set[${BookmarkIter.Value.ID}]
			BookmarkIter:Next
			do
			{
				BM:Concat[",${BookmarkIter.Value.ID}"]
			}
			while ${BookmarkIter:Next(exists)}
		}
		relay all Event[HERE]:Execute[${BM}]
	}

	member:bool AtHomeBase()
	{
		variable index:agentmission amIndex
		variable index:bookmark mbIndex
		variable iterator amIterator
		variable iterator mbIterator
		EVE:GetAgentMissions[amIndex]
		amIndex:GetIterator[amIterator]

		if ${amIterator:First(exists)}
		{
			do
			{
				if ${amIterator.Value.AgentID} == ${Agents.AgentID}
				{
					amIterator.Value:GetBookmarks[mbIndex]
					mbIndex:GetIterator[mbIterator]

					if ${mbIterator:First(exists)}
					{
						do
						{
							UI:UpdateConsole["obj_Agents: DEBUG: mbIterator.Value.LocationType = ${mbIterator.Value.LocationType}"]
							if ${mbIterator.Value.LocationType.Equal["agenthomebase"]} || \
							   ${mbIterator.Value.LocationType.Equal["objective"]}
							{
								if ${mbIterator.Value.ItemID.Equal[${Me.Station.ID}]}
								{
									return TRUE
								}
							}
						}
						while ${mbIterator:Next(exists)}
					}
				}
			}
			while ${amIterator:Next(exists)}
		}
		else
		{
			UI:UpdateConsole["obj_Missions:AtHomeBase: No Missions found."]
		}
		return FALSE
	}
	function WarpToHomeBase()
	{
		variable index:agentmission amIndex
		variable index:bookmark mbIndex
		variable iterator amIterator
		variable iterator mbIterator
		EVE:GetAgentMissions[amIndex]
		amIndex:GetIterator[amIterator]
		if ${amIterator:First(exists)}
		{
			do
			{
				if ${amIterator.Value.AgentID} == ${Agents.AgentID}
				{
					amIterator.Value:GetBookmarks[mbIndex]
					mbIndex:GetIterator[mbIterator]

					if ${mbIterator:First(exists)}
					{
						do
						{
							UI:UpdateConsole["obj_Agents: DEBUG: mbIterator.Value.LocationType = ${mbIterator.Value.LocationType}"]
							if ${mbIterator.Value.LocationType.Equal["agenthomebase"]} || \
							   ${mbIterator.Value.LocationType.Equal["objective"]}
							{
								while !${This.AtHomeBase}
								{
									if ${mbIterator.Value.ID} < 0
									{
										UI:UpdateConsole["NULL bookmark found, calling WarpToHomeBase again and then terminating this thread."]
										call This.WarpToHomeBase
										return
									}
									UI:UpdateConsole["Warping to ${mbIterator.Value.ID} shouldn't happen more than once but we'll see. "]
									call Ship.WarpToBookMark ${mbIterator.Value.ID}
								}
								;mbIterator.Value:SetDestination
								;EVE:Execute[CmdToggleAutopilot]
								;while ${Me.AutoPilotOn} && ${Me.Station} != ${mbIterator.Value.ItemID}
								;{
								;	wait 100
								;}
								return
							}
						}
						while ${mbIterator:Next(exists)}
					}
				}
			}
			while ${amIterator:Next(exists)}
		}
	}

   member:bool HaveMishItem()
   {
		variable index:item cargo
		MyShip:GetCargo[cargo]
		cargo:RemoveByQuery[${LavishScript.CreateQuery[TypeID != "${This.MissionCache.TypeID[${Agents.AgentID}]}"]}]
		cargo:Collapse
		if ${cargo.Used} > 0 || ${This.MissionCache.Volume[${Agents.AgentID}]} == 0 
		{
			;UI:UpdateConsole["Found mish item in cargo or no mish required for mission."]
			if ${cargo[0].Volume} >= ${This.MissionCache.Volume[${Agents.AgentID}]}
			{
				return TRUE
			}
		}
		return FALSE
   }
}
