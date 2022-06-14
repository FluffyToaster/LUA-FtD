-- Adjustable Parameters

-- Important! This is the 1-indexed list of all frag warheads on the missile
warheadIndices = {9, 10, 11, 12, 13, 14}

-- Important! This is the index of the mainframe to which the missiles are connected.
mainframeIndex = 0

-- Number of seconds beyond which the missile will predict no movement.
-- Setting this lower saves fuel on extraneous movement but may negatively impact accuracy
lookaheadLimit = 6

-- Factor by which we divide all predicted y-axis changes
-- Set this to anything above 1 to make the missile "underestimate" altitude changes
-- This can be good for wobbly targets: if they temporarily pitch up, the missile won't aim for an
-- intercept somewhere in the stratosphere. Can also adjust lookaheadLimit for this.
-- If you don't care, leave this at 1.0 for best accuracy
yAxisLookaheadDivider = 1.0

-- Limit on thrust control. If the target is more than this number of seconds away,
-- set the thrust to the default value (below)
-- If you trust the thrust heuristic, you can set this high to always apply custom thrust
controlThrustWithinTime = 100

-- Never set a thrust higher than this value. Can help to save fuel and avoid excessive speed
maxThrust = 300

-- Thrust on which we base all thrust heuristics. If you set this lower, the missile will go slower
-- in ALL cases (the custom thrust is ADDED to this value)
defaultThrust = 190

-- Value that adjusts how much we IGNORE priority
-- In practice, this number is the required priority difference to get a 2:1 missile allocation
-- If this value is 100, and there are two targets, their priorities must differ by 100 to have 2/3 of the missiles go to the higher prio target
-- Setting this value to 0 means the lowest prio target never gets missiles
-- Set this value very high to ignore priority calculations and divide equally (not recommended)
priorityEqualiser = 100

-- Determine within what time we start keeping track of the desired elevation of frag warhead.
-- This value can (and should) be pretty small, for performance reasons
controlFragElevationWithinTime = 0.5

-- Set this value above 0 to detonate the frag warhead before actual impact. Good against soft targets.

prematureFiringDistance = 0

targetMapping = {}
targetMappingSize = 0
missileMapping = {}
missileMappingSize = 0
targetAllocation = {}
targetAllocationSize = 0
allocatedMissiles = {}

priorities = {}
minPriority = 0
sumPriority = 0

function RunSafe(f, I)
 local status, exception = pcall(f, I)
 if not status then
  I:LogToHud("Exception in " .. tostring(f) .. ": " .. tostring(exception))
 end
end

function Update(I)
 I:ClearLogs()
 BuildIndices(I)
 UpdateTargetAllocation(I)
 ControlMissiles(I)
end

function BuildIndices(I)
 -- build targets index and track priorities
 targets = I:GetNumberOfTargets(mainframeIndex)
 targetMapping = {}
 targetMappingSize = 0

 priorities = {}
 minPriority = 100000
 sumPriority = 0
 
 for ti=0,targets-1,1 do
  local tInfo = I:GetTargetInfo(mainframeIndex, ti)
  targetMapping[tInfo.Id] = ti
  targetMappingSize = targetMappingSize + 1

  score = tInfo.Score
  if score == nil then score = 0 end

  priorities[tInfo.Id] = score
  minPriority = math.min(score, minPriority)
  sumPriority = sumPriority + score
 end
 
 -- articifially drop the minPriority to increase all scores a bit
 minPriority = minPriority - priorityEqualiser
 sumPriority = sumPriority - (minPriority * targets)

 -- build missiles index
 transceivers = I:GetLuaTransceiverCount()
 missileMapping = {}
 missileMappingSize = 0
 for transIndex=0,transceivers-1,1 do
  missiles = I:GetLuaControlledMissileCount(transIndex)
  for missileIndex=0,missiles-1,1 do
   missileMapping[I:GetLuaControlledMissileInfo(transIndex,missileIndex).Id] = {transIndex, missileIndex}
   missileMappingSize = missileMappingSize + 1
  end
 end
 I:Log("mm "..missileMappingSize)
 I:Log("ta "..targetAllocationSize)
 I:Log("tm "..targetMappingSize)
end

function UpdateTargetAllocation(I)
 targets = I:GetNumberOfTargets(mainframeIndex)
 if targets < targetAllocationSize then
  for k, v in pairs(targetAllocation) do
   if targetMapping[k] == nil then
    I:LogToHud("Target died: " .. k)
    for k2, v2 in pairs(v) do
     allocatedMissiles[v2] = nil
    end
    targetAllocation[k] = nil
    targetAllocationSize = targetAllocationSize - 1
   end
  
  end
 elseif targets > targetAllocationSize then
  -- find the new targets
  for k, _ in pairs(targetMapping) do
   if targetAllocation[k] == nil then
    I:LogToHud("New target spotted: " .. k)
    targetAllocation[k] = {}
    targetAllocationSize = targetAllocationSize + 1
   end
  end
 end

 -- remove nonexistent missiles from targetAllocation
 for k, v in pairs(targetAllocation) do
  ClearIfNotInMissileMapping(I, v)
 end
 
 -- find non-allocated missiles and assign them to any target that is under the threshold
 for mId, _ in pairs(missileMapping) do
  if allocatedMissiles[mId] == nil then
   for k, v in pairs(targetAllocation) do
    -- scale the missiles per target by the score of this target
    if #v < (missileMappingSize * (priorities[k] - minPriority) / sumPriority) then
     table.insert(v, mId)
     allocatedMissiles[mId] = true
     break
    end
   end
  end
 end
end


function ControlMissiles(I)
 
 targets = I:GetNumberOfTargets(mainframeIndex)
 
 if targets > 0 then
  I:Log("There are " .. targets .. " targets!")
  for targetId, assignedList in pairs(targetAllocation) do
   for _, missileId in pairs(assignedList) do

    temp = missileMapping[missileId]
    if temp == nil then goto continue end
    -- //dry-heaves//
    luaIndex = temp[1]
    missileIndex = temp[2]
    mInfo = I:GetLuaControlledMissileInfo(luaIndex, missileIndex)
	
    targetIndex = targetMapping[targetId]
    if targetIndex == nil then goto continue end
    tInfo = I:GetTargetPositionInfo(mainframeIndex, targetIndex)
    tPos = tInfo.Position

    relativeSpeed = (mInfo.Velocity - tInfo.Velocity).magnitude
    mPos = mInfo.Position
    mtDist = (mInfo.Position - tInfo.Position).magnitude

    timeToTarget = math.min(mtDist / relativeSpeed, lookaheadLimit)

    predictedPos = tPos + Vector3.Scale(tInfo.Velocity, Vector3(timeToTarget, 
                                                                timeToTarget/yAxisLookaheadDivider, 
                                                                timeToTarget))
   
    -- Vector from us to predicted position
    idealVelocity = predictedPos - mPos 

    -- difference between our heading and where we should be heading (to the predictedPos)
    if Vector3.Angle(mInfo.Velocity, idealVelocity) > 5 then
      oofVector = idealVelocity - (mInfo.Velocity.normalized * idealVelocity.magnitude)
    else
      oofVector = Vector3.zero
    end

    if timeToTarget < 1 then
      oofVector = (2 - timeToTarget) * oofVector
    end

    goalPos = predictedPos + oofVector
    goalPos.y = math.max(1, goalPos.y)
   
    I:SetLuaControlledMissileAimPoint(luaIndex, missileIndex, goalPos.x, goalPos.y, goalPos.z)

    -- set our thrust based on all info calculated above
    -- we define a 'confidence' of the target approach
    
    if timeToTarget < controlThrustWithinTime then
      local angleToIdeal = Vector3.Angle(mInfo.Velocity, idealVelocity)
      local confidence = ((mInfo.Velocity.magnitude - relativeSpeed)) + (timeToTarget*10) - (angleToIdeal)
      targetThrust = defaultThrust + confidence
    else
      targetThrust = defaultThrust
    end

    targetThrust = math.min(targetThrust, maxThrust)

    SetMissileThrust(I, luaIndex, missileIndex, targetThrust)
    
    -- change the frag warhead elevation angles if the distance is lower
    if timeToTarget < controlFragElevationWithinTime then
      -- find the approximate elevation to target
      -- this is not the best way to calculate this but it's fast enough
      local xzDist = math.sqrt((mPos.x - tPos.x) * (mPos.x - tPos.x) + (mPos.z - tPos.z) * (mPos.z - tPos.z))
      local approxYDiff = tPos.y - (mPos.y + (mInfo.Velocity.normalized * xzDist).y)
      local approxElev = math.deg(math.atan(approxYDiff / xzDist))
      -- consider dividing to keep the elevation not too silly
      if prematureFiringDistance == 0 then
        approxElev = approxElev / 1.2
      end

      -- check for NaN
      if approxElev == approxElev then
        -- clamp within -90 to 90
        approxElev = math.min(90, math.max(-90, approxElev))
        SetFragElevations(I, luaIndex, missileIndex, approxElev)
      else
        SetFragElevations(I, luaIndex, missileIndex, 0)
        I:LogToHud("Missile elevation NaN")
      end
    end

    -- temp: detonate prematurely for fun yeets
    if mtDist < prematureFiringDistance then
      I:DetonateLuaControlledMissile(luaIndex,missileIndex)
    end
    ::continue::
   end
  end
 else
  I:Log("No Targets")
 end
end

function SetMissileThrust(I, transIndex, missileIndex, thrust)
 I:GetMissileInfo(transIndex,missileIndex).Parts[1]:SendRegister(2, thrust)
end

function SetFragElevations(I, transIndex, missileIndex, elevation)
 local parts = I:GetMissileInfo(transIndex,missileIndex).Parts
 for _, warheadIndex in pairs(warheadIndices) do
  parts[warheadIndex]:SendRegister(2, elevation)
 end
end

function ClearIfNotInMissileMapping(I, t)
 local j, n = 1, #t;
 for i=1,n do
  if (missileMapping[t[i]] ~= nil) then
   -- Move i's kept value to j's position, if it's not already there.
   if (i ~= j) then
    t[j] = t[i];
    t[i] = nil;
   end
   j = j + 1; -- Increment position of where we'll place the next kept value.
  else
   I:Log("Removed a missile from this array")
   allocatedMissiles[t[i]] = nil
   t[i] = nil;
  end
 end
 return t;
end