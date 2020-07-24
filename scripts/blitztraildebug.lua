require "/scripts/vec2.lua"
require "/scripts/util.lua"

function init()
	self.lastPos = config.getParameter("lastPos")
	--self.curPos = config.getParameter("curPos")
	--self.iter = config.getParameter("iter")
	
	self.points = config.getParameter("points")
end

function update(dt)
	world.debugPoint(self.lastPos, "blue")
	--world.debugPoint(self.curPos, "red")
	--world.debugPoint(self.posCalc, "white")
	--world.debugText(tostring(self.iter), vec2.add(mcontroller.position(), {1, 1}), "green")

	for i, v in pairs(self.points) do
		world.debugPoint(self.points[i], "white")
		world.debugText(tostring(i), vec2.add(self.points[i], {0.1, 0.1}), "red")
	end
	
	world.debugLine(mcontroller.position(), self.lastPos, "white")
	
	--drawVelocity(self.lastPos, self.lastVel, lengthCalc)
end

function drawVelocity(pos, vel, dist)
	local angle = vec2.mul(vec2.norm(vel), dist)
	local endPos = vec2.add(pos, angle)
	
	
	world.debugLine(pos, alongAngle(pos, vel, dist), "blue")
end

function alongAngle(pos, angle, dist)
	local u = vec2.norm(angle)
	local du = vec2.mul(u, dist)
	return vec2.add(pos, du)
end