require "/scripts/util.lua"
require "/scripts/companions/util.lua"
require "/scripts/messageutil.lua"
require "/scripts/capturephasic.lua"

function init()
  targets = {}
end

function update(dt)
  promises:update()

  targets = world.monsterQuery(mcontroller.position(), 1, {
    withoutEntityId = projectile.sourceEntity(),
    order = "nearest"
  })

  for _, target in ipairs(targets) do
    if world.entityTypeName(target) == "erchiusghost" then
      promises:add(world.sendEntityMessage(target, "tameInter", projectile.sourceEntity()), function (id)
        if id then
        promises:add(world.sendEntityMessage (id, "pet.attemptCapture", projectile.sourceEntity()), function (pet)
          self.pet = pet
        end)
        end
      end)
      end
  end
end

--function hit(entityId)
--  if self.hit then return end
--  if world.isMonster(entityId) then
--    self.hit = true
--
--    -- If a monster doesn't implement pet.attemptCapture or its response is nil
--    -- then it isn't caught.
--    promises:add(world.sendEntityMessage(entityId, "pet.attemptCapture", projectile.sourceEntity()), function (pet)
--        self.pet = pet
--      end)
--  end
--end

function shouldDestroy()
  return projectile.timeToLive() <= 0 and promises:empty()
end

function destroy()
  if self.pet then
    spawnFilledPod(self.pet)
  else
    spawnEmptyPod()
  end
end

function spawnEmptyPod()
  world.spawnItem("capturepodphasic", mcontroller.position(), 1)
end

function spawnFilledPod(pet)
  local pod = createFilledPodPhasic(pet)
  world.spawnItem(pod.name, mcontroller.position(), pod.count, pod.parameters)
end
