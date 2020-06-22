require "/scripts/util.lua"
require "/scripts/vec2.lua"

function update()
  localAnimator.clearDrawables()
  local drawables = {}
  
  local doAnim = animationConfig.animationParameter("doAnim")
  local dispDir = animationConfig.animationParameter("ammoDisplayDirectory")
  local dispNum = animationConfig.animationParameter("ammoDisplayQuantity")
  local dispOffset = animationConfig.animationParameter("ammoDisplayOffset")
  local dispScale = animationConfig.animationParameter("ammoDisplayScale")
  
  if doAnim then
    if dispDir and dispNum then
        localAnimator.addDrawable({
          --image = dispDir .. dispNum .. ".png",
          image = dispDir .. ":" .. dispNum,
          position = vec2.add(activeItemAnimation.ownerAimPosition(), dispOffset),
		  fullbright = true,
		  scale = dispScale
        }, "overlay")
    end
  end
end
