-- Copyright (c) 2010 sk89q <http://www.sk89q.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local function cn(n)
    n = math.floor(n * 10) / 10
    return n
end

function TOOL:HasValidActive()
    if not ValidEntity(self.ActiveE2) or not self.ActiveE2.context.data or
        not self.ActiveE2.context.data.holos then
        SendUserMessage("WireHoloDesignerNoE2", self:GetOwner())
        return false
    end
    return true
end

function TOOL:SendHolograms()
    if not self:HasValidActive() then return end
    if self.LastSend and RealTime() - self.LastSend < 0.3 then return end
    
    local holos = {}
    
    for index, holo in pairs(self.ActiveE2.context.data.holos) do
        if holo and ValidEntity(holo.ent) then
            holos[index] = holo.ent:EntIndex()
        end
    end
    
    datastream.StreamToClients(self:GetOwner(), "HoloDesignerList", { holos = holos })
    
    self.LastSend = RealTime()
end

function TOOL:SendHologram(holoIndex)
    if not self:HasValidActive() then return end
    local holo = wire_holograms.CheckIndex(self.ActiveE2.context, holoIndex)
    if holo then
        SendUserMessage("WHDHolo", self:GetOwner(), holoIndex, holo.ent:EntIndex())
    end
end

function TOOL:SendE2Code(name, code)
    if not self:HasValidActive() then return end
    
    local chunksize = 200
    local chunks = math.ceil(code:len() / chunksize)
    
    umsg.Start("wire_expression2_download", self:GetOwner())
    umsg.Short(chunks)
    umsg.String(name)
    umsg.End()

    for i = 0,chunks do
        umsg.Start("wire_expression2_download", self:GetOwner())
        umsg.Short(i)
        umsg.String(code:sub(i * chunksize + 1, (i + 1) * chunksize))
        umsg.End()
    end
    
    self.ActiveE2:Prepare(self:GetOwner())
end

function TOOL:GenerateE2()
    if not self:HasValidActive() then return end
    if self.LastSend and RealTime() - self.LastSend < 1 then return end
    
    local code = "# Generated by the Wire Holo Designer STool\n"
    code = code .. "# http://stramic.com\n"
    
    local holoEntIndex = {}
    
    for index, holo in pairs(self.ActiveE2.context.data.holos) do
        if holo and ValidEntity(holo.ent) then
            holoEntIndex[holo.ent] = index
            
            local r, g, b, a = holo.ent:GetColor()
            local pos = self.ActiveE2:WorldToLocal(holo.ent:GetPos())
            local ang = holo.ent:GetAngles()
            local model = holo.ent:GetModel()
            local mat = holo.ent:GetMaterial()
            local skin = holo.ent:GetSkin()
            
            if r ~= 255 or g ~= 255 or b ~= 255 then
                code = code ..
                    Format("holoCreate(%d, entity():toWorld(vec(%g, %g, %g)), " ..
                        "vec(%g, %g, %g), ang(%g, %g, %g), vec(%g, %g, %g))\n",
                        index, cn(pos.x), cn(pos.y), cn(pos.z),
                        cn(holo.scale.x), cn(holo.scale.y), cn(holo.scale.z),
                        cn(ang.p), cn(ang.y), cn(ang.r), r, g, b)
            else
                code = code ..
                    Format("holoCreate(%d, entity():toWorld(vec(%g, %g, %g)), " ..
                        "vec(%g, %g, %g), ang(%g, %g, %g))\n",
                        index, cn(pos.x), cn(pos.y), cn(pos.z),
                        cn(holo.scale.x), cn(holo.scale.y), cn(holo.scale.z),
                        cn(ang.p), cn(ang.y), cn(ang.r))
            end
            
            local vanillaModel = model:lower():match("models/holograms/([^%.]+)%.mdl")
            if vanillaModel then
                code = code ..
                    Format("holoModel(%d, %q)\n", index, vanillaModel)
            else
                code = code ..
                    Format("holoModelAny(%d, %q)\n", index, model)
            end
            
            if mat ~= "" then
                code = code ..
                    Format("holoMaterial(%d, %q)\n", index, mat)
            end
            
            if skin ~= 0 then
                code = code ..
                    Format("holoSkin(%d, %d)\n", index, skin)
            end
        end
    end
    
    for index, holo in pairs(self.ActiveE2.context.data.holos) do
        if holo and ValidEntity(holo.ent) then
            local parent = holo.ent:GetParent()
            
            if parent:IsValid() and holoEntIndex[parent] then
                code = code ..
                    Format("holoParent(%d, %d)\n", index, holoEntIndex[parent])
            end
        end
    end
    
    self:SendE2Code("holo_designer", code)
end

function TOOL:ClearSelection()
    self:GetOwner():ConCommand("wire_holo_designer_clear")
    self.ActiveE2 = nil
end

function TOOL:LeftClick(tr)
    if not ValidEntity(tr.Entity) then return end
    
    if tr.Entity:GetClass() == "gmod_wire_expression2" then
        self.ActiveE2 = tr.Entity
        self:SendHolograms()
    end
    
    return true
end

function TOOL:Reload(tr)
    if not self:HasValidActive() then return end
    
    self:ClearSelection()
    
    return false
end

function TOOL:Act(forwards, holoIndex, action, param, param2, param3)
    if not self:HasValidActive() then return end
    local shift = self:GetOwner():KeyDown(IN_SPEED)
    local alt = self:GetOwner():KeyDown(IN_WALK)
    
    local holoIndex = math.floor(tonumber(holoIndex) or 0)
    if holoIndex < 0 then return end -- No global holograms!
    local holo = wire_holograms.CheckIndex(self.ActiveE2.context, holoIndex)
    if not holo then return end
    
    if action == "move" then
        local amt = math.Clamp(self:GetClientNumber("move_amt"), 0.01, 500)
        if alt and shift then amt = 0.1
        elseif alt then amt = 1
        elseif shift then amt = amt * 2 end
        amt = amt * (forwards and 1 or -1)
        
        if param == "x" then
            holo.ent:SetPos(holo.ent:GetPos() + Vector(amt, 0, 0))
        elseif param == "y" then
            holo.ent:SetPos(holo.ent:GetPos() + Vector(0, amt, 0))
        elseif param == "z" then
            holo.ent:SetPos(holo.ent:GetPos() + Vector(0, 0, amt))
        end
    elseif action == "rotate" then
        local amt = math.Clamp(self:GetClientNumber("rotate_amt"), 0.01, 360)
        if alt and shift then amt = 0.01
        elseif alt then amt = 0.1
        elseif shift then amt = amt * 2 end
        amt = amt * (forwards and 1 or -1)
        
        if param == "p" then
            holo.ent:SetAngles(holo.ent:GetAngles() + Angle(amt, 0, 0))
        elseif param == "y" then
            holo.ent:SetAngles(holo.ent:GetAngles() + Angle(0, amt, 0))
        elseif param == "r" then
            holo.ent:SetAngles(holo.ent:GetAngles() + Angle(0, 0, amt))
        end
    elseif action == "scale" then
        local amt = math.Clamp(self:GetClientNumber("scale_amt"), 0.01, 500)
        if alt and shift then amt = 0.01
        elseif alt then amt = 0.1
        elseif shift then amt = amt * 2 end
        amt = amt * (forwards and 1 or -1)
        
        if param == "x" then
            wire_holograms.rescale(holo, holo.scale + Vector(amt, 0, 0))
        elseif param == "y" then
            wire_holograms.rescale(holo, holo.scale + Vector(0, amt, 0))
        elseif param == "z" then
            wire_holograms.rescale(holo, holo.scale + Vector(0, 0, amt))
        elseif param == "linked" then
            wire_holograms.rescale(holo, holo.scale + Vector(amt, amt, amt))
        end
        wire_holograms.postexec(self.ActiveE2.context)
    elseif action == "pos" then
        local e2Pos = self.ActiveE2:GetPos()
        local x = math.Clamp(tonumber(param) or 0, e2Pos.x - 10000, e2Pos.x + 10000)
        local y = math.Clamp(tonumber(param2) or 0, e2Pos.y - 10000, e2Pos.y + 10000)
        local z = math.Clamp(tonumber(param3) or 0, e2Pos.z - 10000, e2Pos.z + 10000)
        holo.ent:SetPos(Vector(x, y, z))
    elseif action == "ang" then
        local p = (tonumber(param) or 0) % 360
        local y = (tonumber(param2) or 0) % 360
        local r = (tonumber(param3) or 0) % 360
        holo.ent:SetAngles(Angle(p, y, r))
    elseif action == "material" then
        holo.ent:SetMaterial(tostring(param))
    elseif action == "skin" then
        local skin = tonumber(param) or 0
        skin = skin - skin % 1
        holo.ent:SetSkin(skin)
    elseif action == "color" then
        local r, g, b, a = holo.ent:GetColor()
        local r = math.Clamp(tonumber(param) or 0, 0, 255)
        local g = math.Clamp(tonumber(param2) or 0, 0, 255)
        local b = math.Clamp(tonumber(param3) or 0, 0, 255)
        holo.ent:SetColor(r, g, b, a)
    elseif action == "alpha" then
        local r, g, b = holo.ent:GetColor()
        local a = math.Clamp(tonumber(param) or 0, 0, 255)
        holo.ent:SetColor(r, g, b, a)
    elseif action == "model" then
        local model = tostring(param)
        if wire_holograms.ModelList[model] then
            holo.ent:SetModel(Model("models/Holograms/" .. model .. ".mdl"))
        end
    elseif action == "delete" then
        wire_holograms.removeholo(self.ActiveE2.context, holoIndex)
        wire_holograms.postexec(self.ActiveE2.context)
    end
end

concommand.Add("whd_f", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    tool:Act(true, args[1], args[2], args[3])
end)

concommand.Add("whd_b", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    tool:Act(false, args[1], args[2], args[3])
end)

concommand.Add("whd_act", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    tool:Act(false, args[1], args[2], args[3], args[4], args[5])
end)

concommand.Add("wire_holo_designer_refresh", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    tool:SendHolograms()
end)

concommand.Add("whd_create", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    if not tool:HasValidActive() then return end
    local index
    
    if args[1] then
        index = math.floor(tonumber(args[1]) or 0)
        if index <= 0 then return end
    else
        for i = 1, 100 do
            local holo = wire_holograms.CheckIndex(tool.ActiveE2.context, i)
            if not holo then
                index = i
                break
            end
        end
    end
    
    local holo = wire_holograms.CheckIndex(tool.ActiveE2.context, index)
    if not holo and not wire_holograms.CanCreateHolo(tool.ActiveE2.context) then
        return
    end
    
    local ent = wire_holograms.CreateHolo(tool.ActiveE2.context, index,
        tool.ActiveE2:GetPos())
    if ValidEntity(ent) then
        tool:SendHologram(index)
    end
end)

concommand.Add("wire_holo_designer_generate", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    if not tool:HasValidActive() then return end
    tool:GenerateE2()
end)

concommand.Add("whd_sel", function(ply, cmd, args)
    if not ValidEntity(ply) then return end
    local tool = ply:GetTool("wire_holo_designer")
    if not tool:HasValidActive() then return end
    
    -- This is very hacky!
    for index, holo in pairs(tool.ActiveE2.context.data.holos) do
        if ValidEntity(holo.ent) then
            holo.ent:SetSolid(SOLID_BBOX)
        end
    end
    
    -- This doesn't take into account scaling
    local data = {}
    data.start = ply:GetShootPos()
    data.endpos = data.start + ply:EyeAngles():Forward() * 1000
    data.filter = ply
    local tr = util.TraceLine(data)
    
    for index, holo in pairs(tool.ActiveE2.context.data.holos) do
        if ValidEntity(holo.ent) then
            holo.ent:SetSolid(SOLID_NONE)
        end
    end
    
    if tr.Entity:IsValid() and tr.Entity:GetClass() == "gmod_wire_hologram" then
        ply:ConCommand(Format("whd_s %d", tr.Entity:EntIndex()))
        
        local wep = ply:GetWeapon("gmod_tool")
        if ValidEntity(wep) then
            wep:DoShootEffect(tr.HitPos, tr.HitNormal, holoEnt, 0)
        end
    end
    
    return true
end)

hook.Add("EntityRemoved", "WireHoloDesigner", function(ent)
    if ValidEntity(ent) and ent:GetClass() == "gmod_wire_expression2" then
        if ValidEntity(ent.player) then
            local tool = ent.player:GetTool("wire_holo_designer")
            if tool.ActiveE2 == ent then
                tool:ClearSelection()
            end
        end
    end
end)