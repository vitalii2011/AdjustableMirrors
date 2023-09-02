--#######################################################################################
--### Create the table holding all of the info from the mod. Although we do have access  
--### to anything created in the table for the AdjustableMirrors_Register.lua file aswell
--### which is something I suppose the giants engine is doing for us. So if I at any 
--### point use something without importing/initializing it first. Chances are that has 
--### already happened in the register file. An example is the g_AMDebug library.
--### And remember that anything in this file is run on a per instance basis. So fx.
--### onLoad will run for as many times as there are vehicles with the specialization.
--#######################################################################################
AdjustableMirrors = {}
--Modwide version, should be set in AdjustableMirrors_Register.lua
AdjustableMirrors.version = "Unspecified Version"
AdjustableMirrors.modName = "None"
AdjustableMirrors.TEXT_COLOR = {0.5, 1, 0.5, 1}  -- RGBA

--#######################################################################################
--### Check if certain things are present before going further with the mod, 
--### runs when entering the savegame and is run once per specialization it is registered
--### to. This mod handles the checks in AdjustableMirrors_Register.lua so there are no 
--### specialization checks here
--#######################################################################################
function AdjustableMirrors.prerequisitesPresent(specializations)
    return true
end

--#######################################################################################
--### Can be used to expose a function directly into the self object. So fx. making it so
--### you could call a function directly by writing self:function(arg1, arg2) instead of 
--### specialization.function(self, arg1, arg2) I don't know why you would do that though
--### since this might actually clutter stuff instead of keeping things neat inside of
--### the self.spec_specializationName table
--#######################################################################################
function AdjustableMirrors.registerFunctions(vehicleType)
	g_AMDebug.info("registerFunctions")
end

--#######################################################################################
--### New in FS19. Used to register all of the event listeners. In FS17 you just had to 
--### have the functions present. But now you need to register the ones you need aswell
--### And it looks like this function is run upon each vehicletype getting loaded.
--#######################################################################################
function AdjustableMirrors.registerEventListeners(vehicleType)
	g_AMDebug.info("registerEventListeners")
	--Table holding all the events, makes it a bit easier to read the code
	local events = { "onLoad", 
					  "onPostLoad", 
					  "saveToXMLFile", 
					  "onUpdate", 
					  "onUpdateTick", 
					  "onDraw", 
					  "onReadStream", 
					  "onWriteStream", 
					  "onRegisterActionEvents", 
					  "onEnterVehicle", 
					  "onLeaveVehicle", 
					  "onCameraChanged"}
	--Register the events we want our spec to react to. Make sure that you have functions with the same name
	--defined as the this list
	for _,event in pairs(events) do
		SpecializationUtil.registerEventListener(vehicleType, event, AdjustableMirrors)
	end
end

--#######################################################################################
--### Runs when a vehicle with the specialization is loaded. Usefull if you want to
--### fx. expose something that other mods should be able to use in their own onPostLoad
--#######################################################################################
function AdjustableMirrors:onLoad(savegame)
	g_AMDebug.info("onload" .. g_AMDebug.getIdentity(self))
	--DebugUtil.printTableRecursively(self., '-', 0, 2) --self["spec_FS19_AdjustableMirrors.adjustableMirrors"]
	self.spec_adjustableMirrors = self[("spec_%s.adjustableMirrors"):format(AdjustableMirrors.modName)]
	local spec = self.spec_adjustableMirrors

	spec.has_usable_mirrors = false

	--This could be reduced into one if statement, but it would look horrible and in this
	--way it allows me to write several prints depending on the condition that failed
	if g_dedicatedServerInfo ~= nil then
		g_AMDebug.info("This vehicle is loaded on a dedicated server and therefor does not have mirrors" .. g_AMDebug.getIdentity(self))
		spec.has_usable_mirrors = false
	elseif g_gameSettings:getValue("maxNumMirrors") < 1 then
		g_AMDebug.info("This vehicle is loaded on a client that does not have mirrors enabled" .. g_AMDebug.getIdentity(self))
		spec.has_usable_mirrors = false
	elseif not self.spec_enterable.mirrors or not self.spec_enterable.mirrors[1] then
		g_AMDebug.info("This vehicle does not have mirrors" .. g_AMDebug.getIdentity(self))
		spec.has_usable_mirrors = false
	else
		g_AMDebug.info("This vehicle has usable mirrors" .. g_AMDebug.getIdentity(self))
		spec.has_usable_mirrors = true
	end
end

--#######################################################################################
--### Runs when a vehicle with the specialization has been loaded. Useful if you need to 
--### use some values, that has to be loaded from the savegame first. Also runs when 
--### joining a server and the vehicle is loaded in.
--#######################################################################################
function AdjustableMirrors:onPostLoad(savegame)
	g_AMDebug.info("onPostLoad" .. g_AMDebug.getIdentity(self))
	--Quick reference to the specialization, where we should keep all of our variables
	local spec = self.spec_adjustableMirrors

	--Table for holding all of the new adjustment mirrors
	spec.mirrors = {}

	--Maximum rotation value, for capping the rotation of the mirrors
	spec.max_rotation = math.rad(20)
	if g_server ~= nil then
		if g_dedicatedServerInfo ~= nil then
			g_AMDebug.info("Dedi server")
		else
			g_AMDebug.info("Listen server")
		end
	else 
		g_AMDebug.info("This should be a client")
	end

	--It is only relevant to setup mirrors, if we are able to use them.
	if spec.has_usable_mirrors then
		g_AMDebug.info("Initialization stuff, when we have mirrors")
		
		--Initial camera index
		spec.mirror_index = 1
		--Are we allowed to adjust the mirrors
		spec.mirror_adjustment_enabled = false
		--For knowing when to send out an update event to the server and other clients
		spec.mirrors_have_been_adjusted = false
		--How much we should add to the rotation each time a keypress is detected
		spec.mirror_adjustment_step_size = 0.001
		--Table for holding all of the ID's returned when registering the action events in onRegisterActionEvents
		spec.event_IDs = {}

		--#######################################################################################
		--### Used for adding new adjustable mirrors. They require some more transform groups to
		--### be able to be rotated. This new structure allows for tilt and pan of the mirror
		--### without it clipping through the mirror arm structure of the model.
		--#######################################################################################
		local idx = 1
		local function addMirror(mirror)
			g_AMDebug.info("Adding adjustable mirror #" .. idx .. g_AMDebug.getIdentity(self))
			spec.mirrors[idx] = {}
			spec.mirrors[idx].mirror_ref = mirror
			spec.mirrors[idx].rotation_org = {getRotation(spec.mirrors[idx].mirror_ref.node)}
			spec.mirrors[idx].translation_org = {getTranslation(spec.mirrors[idx].mirror_ref.node)}
			spec.mirrors[idx].base = createTransformGroup("Base")
			spec.mirrors[idx].x0 = 0
			spec.mirrors[idx].y0 = 0
			spec.mirrors[idx].x1 = createTransformGroup("x1")
			spec.mirrors[idx].x2 = createTransformGroup("x2")
			spec.mirrors[idx].y1 = createTransformGroup("y1")
			spec.mirrors[idx].y2 = createTransformGroup("y2")
			link(getParent(spec.mirrors[idx].mirror_ref.node), spec.mirrors[idx].base)
			link(spec.mirrors[idx].base, spec.mirrors[idx].x1)
			link(spec.mirrors[idx].x1, spec.mirrors[idx].x2)
			link(spec.mirrors[idx].x2, spec.mirrors[idx].y1)
			link(spec.mirrors[idx].y1, spec.mirrors[idx].y2)
			link(spec.mirrors[idx].y2, spec.mirrors[idx].mirror_ref.node)
			setTranslation(spec.mirrors[idx].base,unpack(spec.mirrors[idx].translation_org))
			setRotation(spec.mirrors[idx].base,unpack(spec.mirrors[idx].rotation_org))
			setTranslation(spec.mirrors[idx].x1,0,0,-0.25)
			setTranslation(spec.mirrors[idx].x2,0,0,0.5)
			setTranslation(spec.mirrors[idx].y1,-0.14,0,0)
			setTranslation(spec.mirrors[idx].y2,0.28,0,0)
			setTranslation(spec.mirrors[idx].mirror_ref.node,-0.14,0,-0.25)
			setRotation(spec.mirrors[idx].mirror_ref.node,0,0,0)
			idx = idx + 1
		end

		--Add the new structure for every mirror
		for i = 1, #spec.spec_enterable.mirrors do
			addMirror(spec.spec_enterable.mirrors[i])
		end
	end

	--If there was a savegame file to load things from
	if savegame ~= nil then
		local xmlFile = savegame.xmlFile
		g_AMDebug.debug("Savegame Key: " .. savegame.key)
		g_AMDebug.debug("Mod name: " .. Utils.getNoNil(AdjustableMirrors.modName, "Nil"))
		local key = savegame.key .. "." .. AdjustableMirrors.modName .. '.adjustableMirrors'
		g_AMDebug.debug("Full key: " .. key)
		--Load in the modversion saved in the savegame file
		local savegameVersion = xmlFile:getString(key .. "#version")
		if savegameVersion == nil then
			g_AMDebug.info("No savegame data present, defaults are used for mirrors" .. g_AMDebug.getIdentity(self))
		elseif savegameVersion ~= AdjustableMirrors.version then
			g_AMDebug.warning("Savegame data is from mod version " .. savegameVersion .. " while the current mod is version " .. AdjustableMirrors.version .. " therefore mirrors are reset to defaults" .. g_AMDebug.getIdentity(self))
		else
			g_AMDebug.info("Loading savegame mirror settings" .. g_AMDebug.getIdentity(self))
			local idx = 1
			while true do
				local position = xmlFile:getVector(key .. ".mirror" .. idx .. "#position", nil, 2)
				if position == nil then
					g_AMDebug.info("Found " .. idx - 1 .. " mirrors" .. g_AMDebug.getIdentity(self))
					break
				else
					g_AMDebug.debug("x0: " .. position[1] .. ", y0: " .. position[2] .. g_AMDebug.getIdentity(self))
					
					AdjustableMirrors.setMirror(self, idx, unpack(position))
					idx = idx + 1
				end
			end
		end
	end
end

--#######################################################################################
--### Called when saving ingame. The xmlfile is the savegame file and the key already
--### contains the specialization name. DO NOT try to nest more than one tag! So
--### basically you are only allowed to have one '.' in the key you save your data
--### under. If you try to further group your stuff by making subgroups, then you will
--### get weird errors on load of the savegame files. Which to me points to that the xml
--### loading functions can only handle 5 nested xml tags. Since the saving works fine if 
--### you try to do more and it will show up properly in the vehicles.xml file.
--#######################################################################################
function AdjustableMirrors:saveToXMLFile(xmlFile, key)
	--DebugUtil.printTableRecursively(xmlFile, "  ", 0, 0)
	g_AMDebug.info("saveToXMLFile - File: " .. tostring(xmlFile.filename) .. ", Key: " .. key .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors
	xmlFile:setString(key .. "#version", AdjustableMirrors.version)

	for idx, mirror in ipairs(spec.mirrors) do
		g_AMDebug.info("saving mirror" .. idx .. ", x0: " .. mirror.x0 .. ", y0: " .. mirror.y0)
		xmlFile:setVector(key .. ".mirror" .. idx .. "#position", {mirror.x0, mirror.y0}, 2)
		g_AMDebug.info("saved mirror")
	end
end

--#######################################################################################
--### This runs on each frame of the game. So if your framerate is a 100 fps, then this
--### runs a 100 times per second. The dt argument supplies the the frametime since the
--### last frame. So use this to make your code not be framerate dependent.
--#######################################################################################
function AdjustableMirrors:onUpdate(dt, isActiveForInput, isSelected)
	g_AMDebug.debug("onUpdate" .. dt .. ", S: " .. tostring(self.isServer) .. ", C: " .. tostring(self.isClient) .. g_AMDebug.getIdentity(self), 5)
end

--#######################################################################################
--### Same as onUpdate, but it only updates with the network ticks. 
--#######################################################################################
function AdjustableMirrors:onUpdateTick(dt)
	g_AMDebug.debug("onUpdateTick" .. dt .. ", S: " .. tostring(self.isServer) .. ", C: " .. tostring(self.isClient) .. g_AMDebug.getIdentity(self), 5)
end

--#######################################################################################
--### Used for updating drawn stuff like GUI elements
--#######################################################################################
function AdjustableMirrors:onDraw()
	g_AMDebug.debug("onDraw" .. g_AMDebug.getIdentity(self), 5)
	local spec = self.spec_adjustableMirrors

	if spec.mirror_adjustment_enabled == true then
		local x, y, z = getWorldTranslation(spec.mirrors[spec.mirror_index].mirror_ref.node)
		Utils.renderTextAtWorldPosition(x, y, z, g_i18n:getText("info_AM_SelectedMirror"), getCorrectTextSize(0.012), 0, self.TEXT_COLOR)
	end
end

--#######################################################################################
--### This is where the client receives data, when it joins the server. Use this to
--### get data on the initial join and synch the states between client and server.
--#######################################################################################
function AdjustableMirrors:onReadStream(streamID, connection)
	g_AMDebug.info("onReadStream - " .. streamID .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors

	--The first value streamed is the number of mirrors, since this is very dynamic from
	--vehicle to vehicle.
	local numbOfMirrors = streamReadInt8(streamID) 

	--The server does not necessarily have any mirror data, since it does know the existence
	--of mirrors on the vehicle (mirrors are only ever present clientside)
	if numbOfMirrors > 0 then
		g_AMDebug.info("Server has mirror data for " .. numbOfMirrors .. " mirrors")

		local mirrorData = {}

		--Read in all the server data first, to keep synchronization with the server even if we don't have mirrors on the client.
		for idx = 1, numbOfMirrors, 1 do
			mirrorData[idx] = {streamReadFloat32(streamID), streamReadFloat32(streamID)}
		end

		--Loop through all available mirrors and update accordingly 
		--(Should handle the case where a client has less mirrors enabled than the server has info for)
		for idx, mirror in ipairs(spec.mirrors) do
			AdjustableMirrors.setMirror(self, idx, mirrorData[idx][1], mirrorData[idx][2])
		end
	
	else
		g_AMDebug.info("No mirror data stored on server for this vehicle")
	end
end

--#######################################################################################
--### This runs on the server when a client joins. Use this to supply initial synch
--### data with the client.
--#######################################################################################
function AdjustableMirrors:onWriteStream(streamID, connection)
	g_AMDebug.info("onWriteStream - " .. streamID .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors

	g_AMDebug.info("mirrors stored on server: " .. #spec.mirrors)
	--Write out the number of mirrors as the first data value to be synched, so the client
	--knows if it should expect data from the server.
	streamWriteInt8(streamID, #spec.mirrors)

	--Stream the mirror position data to the client, if any.
	for idx, mirror in ipairs(spec.mirrors) do
		g_AMDebug.info("mirror" .. idx .. " x0:" .. mirror.x0 .. " y0:" .. mirror.y0)
		streamWriteFloat32(streamID, mirror.x0)
		streamWriteFloat32(streamID, mirror.y0)
	end
end

--#######################################################################################
--### This is run when someone enters the vehicle.
--#######################################################################################
function AdjustableMirrors:onEnterVehicle()
	g_AMDebug.info("onEnterVehicle" .. g_AMDebug.getIdentity(self))
end

--#######################################################################################
--### This is run when someone leaves the vehicle.
--#######################################################################################
function AdjustableMirrors:onLeaveVehicle()
	g_AMDebug.info("onLeaveVehicle" .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors

	--No need to send an update event unless the mirrors have actually been changed
	if spec.mirrors_have_been_adjusted then
		g_AMDebug.info("Mirrors have changed, sending update event")
		AdjustMirrorsEvent.sendEvent(self)
		spec.mirrors_have_been_adjusted = false
	end
end

--#######################################################################################
--### This function is called when the vehicle state is changed. Fx. when switching to
--### the vehicle or switching implements. It is used to register the current actions
--### that are available to be used for the vehicle.
--### isSelected: true if the current implement/vehicle is selected. This value is always
--### false on a tractor, but will be true on fx. a harvester when it is selected instead 
--### of the header.
--### isOnActiveVehicle: Used to determine if the implement is currently attached to
--### the active vehicle.
--#######################################################################################
function AdjustableMirrors:onRegisterActionEvents(isSelected, isOnActiveVehicle)
	g_AMDebug.info("onRegisterActionEvents, selected: " .. tostring(isSelected) .. ", activeVehicle: " .. tostring(isOnActiveVehicle) .. ", S: " .. tostring(self.isServer) .. ", C: " .. tostring(self.isClient) .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors

	--Actions are only relevant if the mirrors are available
	if spec.has_usable_mirrors then
		--OnRegisterActionEvents is called for everyone when someone enters the vehicle but in this case
		--actions should only be registered if we are on and in control of the vehicle
		if isOnActiveVehicle and self:getIsControlled() then
			-- InputBinding.registerActionEvent(g_inputBinding, actionName, object, functionForTriggerEvent, triggerKeyUp, triggerKeyDown, triggerAlways, isActive)

			-- Register AdjustMirrors action, with the active value to be based on whether or not the camera is inside when we switched
			local _, eventID = g_inputBinding:registerActionEvent(InputAction.AM_AdjustMirrors, self, AdjustableMirrors.onActionAdjustMirrors, false, true, false, self:getActiveCamera().isInside)
			spec.event_IDs[InputAction.AM_AdjustMirrors] = eventID
			
			--Actions that have to do with moving the mirrors around
			local actions_adjust = { InputAction.AM_TiltUp, InputAction.AM_TiltDown, InputAction.AM_TiltLeft, InputAction.AM_TiltRight }

			--Keep the adjustment action events grouped, since they will be toggled on/off at the same time
			spec.event_IDs.adjustment = {}

			-- Register SwitchMirror action, this one is only based on a single keypress and not a continues keypress like the rest of the adjustment actions
			local _, eventID = g_inputBinding:registerActionEvent(InputAction.AM_SwitchMirror, self, AdjustableMirrors.onActionSwitchMirror, false, true, false, false)
			spec.event_IDs.adjustment[InputAction.AM_SwitchMirror] = eventID

			-- Register the rest of the adjustment actions
			for _,actionName in pairs(actions_adjust) do
				local _, eventID = g_inputBinding:registerActionEvent(actionName, self, AdjustableMirrors.onActionAdjustmentCall, false, true, true, false)	
				spec.event_IDs.adjustment[actionName] = eventID
			end
		end
	end
end

--#######################################################################################
--### Callback for the onCameraChanged event, which is triggered when the active camera
--### is changed. This event is fx. raised by the Enterable specialization in the
--### setActiveCameraIndex function.
--#######################################################################################
function AdjustableMirrors:onCameraChanged(activeCamera, camIndex)
	g_AMDebug.info("onCameraChanged - camIndex: " .. camIndex .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors

	--Only relevant to toggle the action event if we have mirrors
	if spec.has_usable_mirrors then

		local eventID = spec.event_IDs[InputAction.AM_AdjustMirrors]

		if activeCamera.isInside  then 
			--Enable the Adjustable Mirror action, to show it when inside the cabin
			g_inputBinding:setActionEventActive(eventID, true)
		else
			--Disable the Adjustable Mirror action, to not show it when outside the cabin view.
			g_inputBinding:setActionEventActive(eventID, false)
		end

		--Disable the adjustment actions, just in case they were enabled when changing camera.
		AdjustableMirrors.updateAdjustmentEvents(self,false)
	end
end

--#######################################################################################
--### Callback for the AdjustMirrors action
--#######################################################################################
function AdjustableMirrors:onActionAdjustMirrors(actionName, keyStatus)
	g_AMDebug.info("onActionAdjustMirrors - " .. actionName .. ", keyStatus: " .. keyStatus .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors
	--Toggles the adjustment actions
	AdjustableMirrors.updateAdjustmentEvents(self)
end

--#######################################################################################
--### Callback for the SwitchMirror action
--#######################################################################################
function AdjustableMirrors:onActionSwitchMirror(actionName, keyStatus)
	g_AMDebug.info("onActionSwitchMirror - " .. actionName .. ", keyStatus: " .. keyStatus .. g_AMDebug.getIdentity(self))
	local spec = self.spec_adjustableMirrors
	
	--Selected the next mirror or loop around to the first one if the last one was selected
	if spec.mirror_index == #spec.mirrors then
		spec.mirror_index = 1
	else
		spec.mirror_index = spec.mirror_index + 1
	end

	g_AMDebug.info("new value of mirror_index: " .. spec.mirror_index)
end

--#######################################################################################
--### Update the event prompts for the adjustment events. If state is nothing, then the
--### function just toggles the state. 
--#######################################################################################
function AdjustableMirrors:updateAdjustmentEvents(state)
	g_AMDebug.info("updateAdjustmentEvents - state: " .. tostring(Utils.getNoNil(state, "Nil")))
	local spec = self.spec_adjustableMirrors
	--If 'state' was supplied then use that, and if not then act as a toggle
	spec.mirror_adjustment_enabled = Utils.getNoNil(state, not spec.mirror_adjustment_enabled)

	if (spec.event_IDs ~= nil) and (spec.event_IDs.adjustment ~= nil) then
		for _, eventID in pairs(spec.event_IDs.adjustment) do
			g_inputBinding:setActionEventActive(eventID, spec.mirror_adjustment_enabled )
			g_inputBinding:setActionEventTextPriority(eventID, GS_PRIO_VERY_HIGH)
		end
	end
end

--#######################################################################################
--### Called when one of the adjustment actions take place
--#######################################################################################
function AdjustableMirrors:onActionAdjustmentCall(actionName, keyStatus, arg4, arg5, arg6)
	g_AMDebug.info("onActionAdjustmentCall - " .. actionName .. ", keyStatus: " .. keyStatus .. g_AMDebug.getIdentity(self), 4)
	local spec = self.spec_adjustableMirrors

	spec.mirrors_have_been_adjusted = true

	local mirror = spec.mirrors[spec.mirror_index]

	--Adjust the mirror depending on which of the adjustment events was called
	if actionName == "AM_TiltDown" then
		AdjustableMirrors.setMirror(self, spec.mirror_index, mirror.x0 - spec.mirror_adjustment_step_size, mirror.y0)
	elseif actionName == "AM_TiltUp" then
		AdjustableMirrors.setMirror(self, spec.mirror_index, mirror.x0 + spec.mirror_adjustment_step_size, mirror.y0)
	elseif actionName == "AM_TiltLeft" then
		AdjustableMirrors.setMirror(self, spec.mirror_index, mirror.x0, mirror.y0 - spec.mirror_adjustment_step_size)
	elseif actionName == "AM_TiltRight" then
		AdjustableMirrors.setMirror(self, spec.mirror_index, mirror.x0, mirror.y0 + spec.mirror_adjustment_step_size)
	end
end

--#######################################################################################
--### Used to update the mirror from new values of x0 and y0
--#######################################################################################
function AdjustableMirrors:setMirror(mirror_idx, new_x0, new_y0)
	g_AMDebug.debug("setMirror" .. g_AMDebug.getIdentity(self), 4)
	local spec = self.spec_adjustableMirrors

	--Just in case that the mirror isn't already present, fx. on the server
	if spec.mirrors[mirror_idx] == nil then
		spec.mirrors[mirror_idx] = {}
	end

	local mirror = spec.mirrors[mirror_idx]

	--Clamps the rotation of the mirrors between -max_rotation and rotation
	mirror.x0 = math.min(spec.max_rotation,math.max(-spec.max_rotation, new_x0))
	mirror.y0 = math.min(spec.max_rotation,math.max(-spec.max_rotation, new_y0))

	--Set the rotations of the individual joints to accomodate the special adjustment pattern.
	--The mirrors hinges at the top or bottom, left or right. Depending on which edge hits the
	--Mirror arm where the mirror is attached
	if spec.has_usable_mirrors then
		setRotation(mirror.x1,math.min(0,mirror.x0),0,0)
		setRotation(mirror.x2,math.max(0,mirror.x0),0,0)
		setRotation(mirror.y1,0,0,math.max(0,mirror.y0))
		setRotation(mirror.y2,0,0,math.min(0,mirror.y0))
	end
end
