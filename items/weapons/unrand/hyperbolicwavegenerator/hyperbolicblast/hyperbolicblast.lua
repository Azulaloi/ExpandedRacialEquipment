require "/scripts/vec2.lua"

function init()
  self.wavePeriod = config.getParameter("wavePeriod") / (2 * math.pi)
  self.waveAmplitude = config.getParameter("waveAmplitude")

  self.timer = self.wavePeriod * 0.25
  local vel = mcontroller.velocity()
  if vel[1] < 0 then
    self.waveAmplitude = -self.waveAmplitude
  end
  self.lastAngle = 0
end

function update(dt)
  self.timer = self.timer + dt
  local newAngle = self.waveAmplitude * math.sin(self.timer / self.wavePeriod)

  mcontroller.setVelocity(vec2.rotate(mcontroller.velocity(), newAngle - self.lastAngle))

  self.lastAngle = newAngle

  local targets = world.monsterQuery(mcontroller.position(), 1, {
    withoutEntityId = projectile.sourceEntity(),
    --includedTypes = {"erchiusghost"},
    order = "nearest"
  })

  for _, target in ipairs(targets) do
    if world.entityTypeName(target) == "erchiusghost" then
      world.sendEntityMessage(target, "applyStatusEffect", "hyperbolicEffect")
    end
  end
end
