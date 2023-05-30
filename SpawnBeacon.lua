-- Slot enabling/disabling is handled through Ciribob's SimpleSlotBlock
-- https://github.com/ciribob/DCS-SimpleSlotBlock
-- If SimpleSlotBlock is not enabled, then having the FARP be "built" will
-- not be a pre-requisite to being able to select the slot. The default
-- value for ssb.enabledFlagValue is 0, so that's what this code assumes.
local SLOT_ENABLE_VALUE = 0
local SLOT_DISABLE_VALUE = 100

-- Group names allowed to build a FARP.
local FARP_DEPLOYER_GROUP_NAMES = {
  "Mi-8 (FARP Deployer) 1",
  "Mi-8 (FARP Deployer) 2"
}
-- Name of the "Invisible FARP" static object that gets moved around.
local FARP_NAME = "Buildable FARP"
-- Group names of the aircraft that is assigned to the buildable FARP.
local FARP_AIRCRAFT_GROUP_NAMES = {
  "FARP AV8B"
}

-- Used to make sure only the active FARP has a marker on it.
local FarpMarkerId = nil

local function EnableSlots(slotNameList)
  for i = 1, #slotNameList do
    trigger.action.setUserFlag(slotNameList[i], SLOT_ENABLE_VALUE)
  end
end

local function DisableSlots(slotNameList)
  for i = 1, #slotNameList do
    trigger.action.setUserFlag(slotNameList[i], SLOT_DISABLE_VALUE)
  end
end

-- Convenience function for printing the mission text.
local function DebugLog(message)
  trigger.action.outText(tostring(message), 10, false)
end

local function Vec3ToMGRSString(vec3)
  local lat, long = coord.LOtoLL(vec3)
  local mgrs = coord.LLtoMGRS(lat, long)
  return mist.tostringMGRS(mgrs, 2)
end

-- The meat of this demo. Will "build" a FARP near the given builderUnit.
-- Expects a table of the following format:
-- {
--    builderUnit: Unit from which the FARP will be built
--    farpName: Name of the "Invisible FARP" to be moved
-- }
-- All this is really doing, is moving the given FARP (which seemingly must
-- be an "Invisible FARP" static?) to a location near the builderUnit.
-- If SimpleSlotBlock is installed, then it will also unlock the slots
-- that were assigned to the FARP.
-- In the mission editor, these slots must be placed on the FARP's original
-- position, and must use one of the "start from ramp" type options so that
-- they continue to snap to the FARP, even after moving.
-- This might be abusing a load bearing bug.
local function BuildFARP(buildInfo)

  local builderUnit = buildInfo.builderUnit
  local farpName = buildInfo.farpName

  if builderUnit == nil then
    DebugLog("Invalid builder unit!")
    return
  end

  if (farpName == nil or StaticObject.getByName(farpName) == nil) then
    DebugLog("Invalid FARP name!")
    return
  end

  -- Require that the builder is stopped and on the ground.
  local speed = mist.vec.mag(builderUnit:getVelocity())
  local agl = builderUnit:getPoint().y - mist.utils.makeVec3GL(builderUnit:getPoint()).y
  if speed > 1  or agl > 10 then
    local message = string.format(
      "FARP Deployer must be stopped and on the ground!\nCurrent speed: %.1f m/s\nCurrent AGL: %.1f m", speed, agl)
    DebugLog(message)
    return
  end

  -- "Build" the FARP in front of the building unit.
  DebugLog("Attempting to build FARP...")
  local buildPosition = builderUnit:getPosition()
  local buildDistance = 50.0
  local buildVec = mist.vec.scalarMult(buildPosition.x, buildDistance)
  local buildPoint = mist.vec.add(buildPosition.p, buildVec)
  buildPoint = mist.utils.makeVec3GL(buildPoint, 0)

  -- Move the FARP object. Seems to require it be the Invisible FARP.
  -- I tried with the other FARP objects and it didn't seem to work.
  DebugLog("At coordinates: " .. Vec3ToMGRSString(buildPoint))
  local teleportVars = {}
  teleportVars.gpName = farpName
  teleportVars.action = "teleport"
  teleportVars.point = buildPoint
  mist.teleportToPoint(teleportVars)

  -- Create a simple map marker. For servers that don't show units,
  -- markers are the best way to show where the FARPs are on the map.
  -- I also haven't figured out how to remove the old FARPs, so this
  -- makes it more obvious which one is the active one...
  local markerVars = {}
  markerVars.pos = buildPoint
  markerVars.text = "Deployable FARP"
  markerVars.markType = 0
  local mark = mist.marker.add(markerVars)

  -- Clean up the old marker to make clear the new FARP position.
  if FarpMarkerId then
    mist.marker.remove(FarpMarkerId)
    DebugLog("Cleaning up old marker...")
  end
  FarpMarkerId = mark.markId

  -- Now that the FARP has been "built" enable the FARP Harriers.
  -- If SimpleSlotBlocker is not installed, this won't do anything.
  EnableSlots(FARP_AIRCRAFT_GROUP_NAMES)
  DebugLog("FARP completed!")

  -- Pop smoke as a visual aid
  trigger.action.smoke(buildPoint, 0)
end

-- Returns true if the given group name is in FARP_DEPLOYER_GROUP_NAMES.
local function isGroupNameABuilder(groupName)
  for i = 1, #FARP_DEPLOYER_GROUP_NAMES do
    if FARP_DEPLOYER_GROUP_NAMES[i] == groupName then return true end
  end
  return false
end

-- If the player has entered a unit inside one of the designated builder
-- groups, give them the command to build a FARP.
-- This is done with the assumption that all players are by themselves in
-- one unit groups.
local function onPlayerEnterUnit(event)
  if event.id ~= 20 then return end
  local unit = event.initiator
  local groupName = unit:getGroup():getName()
  if isGroupNameABuilder(groupName) then
    missionCommands.addCommandForGroup(
      unit:getGroup():getID(),
      "Build FARP", nil,
      BuildFARP,
      { builderUnit = unit, farpName = FARP_NAME })
  end
end

-- Clean up all the commands when the player leaves a unit.
-- This is done with the assumption that all players are by themselves in
-- one unit groups.
local function onPlayerLeaveUnit(event)
  if event.id ~= 21 then return end

  local unit = event.initiator
  local groupName = unit:getGroup():getName()
  if isGroupNameABuilder(groupName) then
    missionCommands.removeItemForGroup(unit:getGroup():getID(), nil)
  end
end

-- Enable the slot blocker, and block off the FARP Harriers
trigger.action.setUserFlag("SSB", 100)
DisableSlots(FARP_AIRCRAFT_GROUP_NAMES)

-- Populate and clean up the F10 radio commands for the FARP builders.
mist.addEventHandler(onPlayerEnterUnit)
mist.addEventHandler(onPlayerLeaveUnit)
