-- the dot product between the vectors (CoM->Spinblock) and (CoM->Missile) is computed to check if the missile is on "our side" of the construct
-- setting this value at 0 only checks if the missile is not literally on the other side
-- you can set this value as high as ~0.75 to make the checking more strict
DOT_PROD_THRESHOLD = 0

-- movement speed of all spinblocks, in radians per second
SPIN_SPEED = 5

-- only affect spinblocks with the following custom name
SPIN_BLOCK_NAME = "jimmy"

function Update(I)
  I:ClearLogs()
  com = I:GetConstructCenterOfMass()
  missiles = I:GetNumberOfWarnings()

  if missiles > 0 then
    subs = I:GetAllSubConstructs()
    for i = 1, #subs do
      if I:IsSpinBlock(subs[i]) then
        -- get subconstruct
        spinfo = I:GetSubConstructInfo(subs[i])

        -- check if we are allowed to move this spin block
        if spinfo.CustomName == SPIN_BLOCK_NAME then
          I:SetSpinBlockContinuousSpeed(subs[i], 10)

          -- find missile
          closestDist = 10000000
          closestInfo = nil
          for i = 0,missiles do
            info = I:GetMissileWarning(i)
            dist = (spinfo.Position - info.Position).magnitude

            -- check if missile is on our side of the center of mass
            toMissile = info.Position - com
            toUs = spinfo.Position - com
            dot = Vector3.Dot(toMissile.normalized, toUs.normalized)

            if dot > DOT_PROD_THRESHOLD and dist < closestDist then
              closestDist = dist
              closestInfo = info
            end
          end

          if closestDist > 1000 then
            I:SetSpinBlockRotationAngle(subs[i], 0)
            goto continue
          end

          mPos = closestInfo.Position

          -- get subconstruct parent
          parent = I:GetParent(subs[i])
          if parent == 0 then
            parentForwards = I:GetConstructForwardVector()
            parentRot = Quaternion.FromToRotation(Vector3(0,0,1), parentForwards)
          else 
            parentForwards = I:GetSubConstructInfo(parent).Forwards
            parentRot = I:GetSubConstructInfo(parent).Rotation
          end

          -- we want to point to the missile
          desired = mPos - spinfo.Position

          -- apply parent rot frame
          desired = Quaternion.Inverse(parentRot) * desired

          -- apply rot frame between spin block and parent
          spinRotationComparedToParent = I:GetSubConstructIdleRotation(subs[i])
          desired = Quaternion.Inverse(spinRotationComparedToParent) * desired

          -- rotation from current parent direction to missile
          desiredRot = Quaternion.FromToRotation(Vector3(0, 0, 1), desired).eulerAngles

          -- always take the y component since the spin block rotates along that axis
          
          I:SetSpinBlockRotationAngle(subs[i], desiredRot.y)
        end
      end
      ::continue::
    end
  end
end