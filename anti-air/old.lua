

lookaheadLimit = 10
yAxisLookaheadDivider = 1.2

mainframeIndex = 0

function Update(I)
 I:ClearLogs()
 targets = I:GetNumberOfTargets(mainframeIndex)
 if targets > 0 then
  I:Log("There are " .. targets .. " targets!")
  -- precalculate the missiles per target using total missile count
  totalMissiles = 0
  for li=0,I:GetLuaTransceiverCount()-1,1 do
   totalMissiles = totalMissiles + I:GetLuaControlledMissileCount(li)
  end
  missilesPerTarget = totalMissiles / targets
  I:Log("mpt "..missilesPerTarget)
 
  -- store a unique id for each missile, an incremental value used to assign it to a target
  mUniqueID = 0
  for luaTransceiverIndex=0,I:GetLuaTransceiverCount()-1,1 do 
   mCount = I:GetLuaControlledMissileCount(luaTransceiverIndex)
   for missileIndex=0,mCount-1,1 do

    -- precheck if missile info is garbage
    mInfo = I:GetLuaControlledMissileInfo(luaTransceiverIndex, missileIndex)
    if not mInfo.Valid then
     I:Log("Yucky invalid missile ID")
     goto continue
    end

    -- super basic missile allocation logic
    -- target index == missile index / (missiles per target)
    tIndex = math.floor(mUniqueID / missilesPerTarget)
    I:Log("mid " .. mUniqueID .. " tindex " .. tIndex)
    I:Log(I:GetTargetInfo(mainframeIndex, tIndex).Id)
    mUniqueID = mUniqueID + 1
    tInfo = I:GetTargetPositionInfo(mainframeIndex, tIndex)
    tPos = tInfo.Position

    relativeSpeed = (mInfo.Velocity - tInfo.Velocity).magnitude
    mPos = mInfo.Position
    mtDist = (mInfo.Position - tInfo.Position).magnitude

    --I:Log("Missile is " .. mtDist .. " meters from target")

    timeToTarget = math.min(mtDist / relativeSpeed, lookaheadLimit)

    predictedPos = tPos + Vector3.Scale(tInfo.Velocity, Vector3(timeToTarget, 
                                                                timeToTarget/yAxisLookaheadDivider, 
                                                                timeToTarget))
   
    -- Vector from us to predicted position
    idealVelocity = predictedPos - mPos 

    -- difference between our heading and where we should be heading (to the predictedPos)
    -- for now we just scale the velocity to match the size of ideal and add this directly to goalPos
    if Vector3.Angle(mInfo.Velocity, idealVelocity) > 5 then
      oofVector = idealVelocity - (mInfo.Velocity.normalized * idealVelocity.magnitude)
    else
      oofVector = Vector3.zero
    end

    goalPos = predictedPos + oofVector
    goalPos.y = math.max(5, goalPos.y)
   
    I:SetLuaControlledMissileAimPoint(luaTransceiverIndex, missileIndex, goalPos.x, goalPos.y, goalPos.z)

    ::continue::
   end
  end
 else
  I:Log("No Targets")
 end
end