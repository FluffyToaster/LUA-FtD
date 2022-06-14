function LogVector(I, txt, v)
  I:Log(txt .. ": " .. v.x .. ", " .. v.y .. ", " .. v.z)
end

function Update(I)
  I:ClearLogs()
  subs = I:GetAllSubConstructs()
  for i = 1, #subs do
    if I:IsSpinBlock(subs[i]) then
      -- find missile
      mWarn = I:GetMissileWarning(0)
      mPos = mWarn.Position

      -- get subconstruct
      spinfo = I:GetSubConstructInfo(subs[i])

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
      
      I:SetSpinBlockContinuousSpeed(subs[i], 10)
      I:SetSpinBlockRotationAngle(subs[i], desiredRot.y)
    end
  end
end