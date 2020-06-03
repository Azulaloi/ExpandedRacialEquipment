require "/scripts/vec2.lua"

function init()
  self.returnOnHit = config.getParameter("returnOnHit", false)
  self.controlForce = config.getParameter("controlForce")
  self.snapDistance = config.getParameter("snapDistance")
  self.timeToLive = config.getParameter("timeToLive")
  self.speed = config.getParameter("speed")

  self.slowDist = config.getParameter("slowDist")
  self.stillDist = config.getParameter("stillDist")
  self.killDist = config.getParameter("killDist")
  self.rushDist = config.getParameter("rushDist")
  self.returning = false
  self.ownerId = projectile.sourceEntity()

  --mcontroller.applyParameters({collisionEnabled=false})

  message.setHandler("projectileIds", projectileIds)

  message.setHandler("setTargetPosition", function(_, _, targetPosition)
      self.targetPosition = targetPosition
    end)

  message.setHandler("addRecoil", function(_, _, value)
   -- mcontroller.addMomentum(value)
    --self.recoilDirection = value
    mcontroller.setYVelocity(50)

  end)
  --self.currentRecoil = nil

  message.setHandler("kill", projectile.die)
  message.setHandler("return", function() self.returning = true end)

end

function update(dt)

  if self.ownerId and world.entityExists(self.ownerId) then

      local toTarget = world.distance(world.entityPosition(self.ownerId), mcontroller.position())

      if self.returning then
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
        if vec2.mag(toTarget) < self.killDist then
          projectile.die()
        end
      elseif vec2.mag(toTarget) < self.stillDist then
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), 0), self.controlForce / 3)
      elseif vec2.mag(toTarget) < self.slowDist then
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed / 3), self.controlForce * 3)
      elseif vec2.mag(toTarget) > self.rushDist then
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed * 3), self.controlForce * 2)
      else
        --        projectile.die()
--      elseif projectile.timeToLive() < self.timeToLive * 0.5 then
--        mcontroller.applyParameters({collisionEnabled=false})
--        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
--      elseif vec2.mag(toTarget) < self.snapDistance then
--        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
--      else

        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), self.controlForce)
      end
  else
    projectile.die()
  end
end

function projectileIds()
  return {entity.id()}
end

function setTargetPosition(targetPosition)
  self.targetPosition = targetPosition
end
