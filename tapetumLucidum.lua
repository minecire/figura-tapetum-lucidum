--require "scripts.config"

local CONFIG = {

    --This is the part of the model with your eyes on it
    MODEL_PART = HUMANOID_MODEL.Root.UpperHalf.Head.Face;

    --This is a texture with just your eyes, set to emissive
    EYES_TEXTURE = textures["textures.humanoid_normal.eyes"];


    --These options are for the ray trace.
    
    --Controls proportion of total allowed instructions to use max per tick
    MAX_INSTRUCTION_PROPORTION = 0.5;

    --The distance at which we start looking for light sources. 
    --not set to 0 because that causes eyes to shine whenever theres a light source very close to model.
    START_DISTANCE = 5;

    --The maximum distance the ray will travel. Set higher for more accuracy, lower for less calculation.
    DISTANCE = 100;
    --The distance that will stepped before checking light level again. Lower for more accuracy, higher for less calculation.
    STEP = 0.1;
    --Eyeshine brightness is dimmed when camera is close to model to prevent flashing. 
    --This controls the nearest distance for which eyes are fully bright.
    FULL_BRIGHTNESS_DISTANCE = 9;


    --These control the distance from a light source where eyeshine is no longer applied.
    --It's scaled with proportion to distance of the light source from the model,
    --So at distance FALL_OFF_DISTANCE, the ray needs to be at most FALL_OFF away for eyeshine to apply.
    --And at 2*FALL_OFF_DISTANCE, ray must be 2*FALL_OFF or closer.
    FALL_OFF = 3;
    FALL_OFF_DISTANCE = 20;


    --These control various sources of eyeshine.

    --Block light is light from placed light sources
    BLOCK_LIGHT_ENABLED = true;
    BLOCK_LIGHT_STRENGTH = 1;

    --Item light is light from held light sources
    ITEM_LIGHT_ENABLED = true;
    ITEM_LIGHT_STRENGTH = 1;

    --Light from the moon
    MOON_LIGHT_ENABLED = true;
    MOON_LIGHT_STRENGTH = 0.3;
    --Controls max angle away from moon eyes will shine
    MOON_LIGHT_ANGLE = 0.1;

    --Light from the sun
    SUN_LIGHT_ENABLED = true;
    SUN_LIGHT_STRENGTH = 1;
    SUN_LIGHT_ANGLE = 0.1;

    --Light from the sky during the day
    DAY_LIGHT_ENABLED = true;
    DAY_LIGHT_STRENGTH = 0.1;
    --Controls the amount of time into the night that eyeshine will still be applied from daylight
    DAY_LIGHT_FADE_LENGTH = 0.2;

}

function events.TICK()
    --Check if tapetum lucidum is enabled
    if(eyesGlowing) then
        --[[
        Ok so. Basically how this whole script works is it's emulating a retroreflector, meaning light that hits eyes should be reflected directly back towards where it came from.
        It does that by essentially casting a ray and checking light levels along the way to find a maximum.
        The ray has to start at the position of the eyes and point towards the position of the camera, so that it's checking for light in the same direction as the camera.
        ]]--
        --Get the position of the current viewer's camera
        cameraPos = client:getCameraPos();
        --And the position of our eyes
        eyesPos = player:getPos() + vec(0, player:getEyeHeight(), 0);


        --Use these to determine the maximum light level, getting a value between 0-1
        highestLightLevel = findHighestLightLevel(eyesPos, cameraPos);
        
        --Set texture so eyes will emit light
        CONFIG.MODEL_PART:setSecondaryRenderType("EMISSIVE");
        CONFIG.MODEL_PART:setSecondaryTexture("CUSTOM", CONFIG.EYES_TEXTURE);
        col = highestLightLevel;
        --Set brightness to highest light level
        CONFIG.MODEL_PART:setSecondaryColor(col, col, col);
    else
        --otherwise disable emissive eyes
        CONFIG.MODEL_PART:setSecondaryRenderType(nil);
        CONFIG.MODEL_PART:setSecondaryTexture(nil);
        end
    end

--disable emissive eyes in gui, cuz it renders wrong and looks weird
function events.RENDER(_, ctx)
    if(ctx == "FIGURA_GUI" or ctx == "MINECRAFT_GUI") then
        CONFIG.MODEL_PART:setSecondaryRenderType(nil);
        CONFIG.MODEL_PART:setSecondaryTexture(nil);
        end
    end

--this boolean describes whether the path the ray takes is clear, to check for skylight/moonlight/sunlight
local sky = true;
function findHighestLightLevel(startPos, endPos)

    --initialize light level variables
    blockLightLevel = 0;
    itemLightLevel = 0;
    moonLightLevel = 0;
    dayLightLevel = 0;
    sunLightLevel = 0;

    maxLightLevel = 0;

    --calculate the difference between the start and end positions
    posDiff = endPos - startPos;

    --each step along the ray, this amount will be added to the position to find the next.
    --calculated as the difference of positions normalized to the step length.
    stepVec = CONFIG.STEP * (1 / posDiff:length()) * posDiff;
    sky = true;
    --to check sky, we need to cast a ray, so anything that requires checking for block light or checking for sky means we need to cast the ray.
    if(CONFIG.MOON_LIGHT_ENABLED or CONFIG.DAY_LIGHT_ENABLED or CONFIG.BLOCK_LIGHT_ENABLED or CONFIG.SUN_LIGHT_ENABLED) then
        blockLightLevel = castEyeshineRay(startPos, stepVec) * CONFIG.BLOCK_LIGHT_STRENGTH;
        end
    if(CONFIG.ITEM_LIGHT_ENABLED) then
        itemLightLevel = findItemLightLevel() * CONFIG.ITEM_LIGHT_STRENGTH;
        end
    --calculate sky light levels only if ray doesnt hit a wall
    if(sky) then
        if(CONFIG.MOON_LIGHT_ENABLED) then
            moonLightLevel = findMoonLightLevel(posDiff) * CONFIG.MOON_LIGHT_STRENGTH;
            end
        if(CONFIG.DAY_LIGHT_ENABLED) then
            dayLightLevel = findDayLightLevel() * CONFIG.DAY_LIGHT_STRENGTH;
            end
        if(CONFIG.SUN_LIGHT_ENABLED) then
            sunLightLevel = findSunLightLevel(posDiff) * CONFIG.SUN_LIGHT_STRENGTH;
            end
        --calculate maximum light level, adding that final zero so we never get a value less than zero
        maxLightLevel = math.max(moonLightLevel, blockLightLevel, itemLightLevel, dayLightLevel, sunLightLevel, 0);
    else
        maxLightLevel = math.max(blockLightLevel, itemLightLevel, 0);
        end

    --finally, dim the brightness if the distance from eyes to camera is small.
    return distanceModify(maxLightLevel, posDiff:length());
    end

function distanceModify(level, distance)
    --scale brightness by distance relative to the full brightness setting
    if(distance < CONFIG.FULL_BRIGHTNESS_DISTANCE) then
        return level * distance/CONFIG.FULL_BRIGHTNESS_DISTANCE;
    else
        --maximum brightness of 1
        return level;
        end
    end

--table to convert moon phase to light level
local phaseToLight = {
    [0] = 1, --full moon
    [1] = 0.75, --waning gibbous
    [2] = 0.5, --waning half
    [3] = 0.25, --waning crescent
    [4] = 0, --new moon
    [5] = 0.25, --waxing crescent
    [6] = 0.5, --waxing half
    [7] = 0.75 --waxing gibbous
}
function findMoonLightLevel(posDiff)
    --get current time of day out of 24000 ticks
    time = world.getTimeOfDay() % 24000;
    --use time to calculate angle of moon in the sky
    moonRot = vec((time/24000 - 1) * 2 * math.pi, math.pi/2,  0);
    --calculate angle of ray
    rot = vec(math.atan(posDiff.y/posDiff.x), math.acos(posDiff.z/posDiff:length()), 0);
    --arctan doesnt give the right angle half the time, it's off by exactly 180 degrees
    if(posDiff.x > 0) then 
        rot.x = rot.x - math.pi; 
        end
    moonLight = 0;
    --compare angles
    if((moonRot-rot):length() < CONFIG.MOON_LIGHT_ANGLE) then
        --use difference of angles and moon phase to calculate a light level
        moonLight = (1-(moonRot-rot):length() / CONFIG.MOON_LIGHT_ANGLE) * phaseToLight[world.getMoonPhase()];
        end
    
    return moonLight;
    end

function findSunLightLevel(posDiff)
    --get current time of day out of 24000 ticks
    time = world.getTimeOfDay();
    --calculate angle of sun in sky
    sunRot = vec(time/24000 * 2 * math.pi, math.pi/2,  0);
    --calculate angle of ray
    rot = vec(math.atan(posDiff.y/posDiff.x), math.acos(posDiff.z/posDiff:length()), 0);

    sunLight = 0;
    --compare angles
    if((sunRot-rot):length() < CONFIG.SUN_LIGHT_ANGLE) then
        --use difference of angles to calculate a light level
        sunLight = (1-(sunRot-rot):length() / CONFIG.SUN_LIGHT_ANGLE);
        end
    
    return sunLight;
    end

function findDayLightLevel()
    --get current time of day
    time = world.getTimeOfDay() % 24000
    if(time < 12000) then
        --if its daytime, return maximum light level
        return 1;
    else
        --otherwise calculate light level based on distance to daytime
        return (math.abs(time - 18000) / 6000 - 1 + CONFIG.DAY_LIGHT_FADE_LENGTH) / CONFIG.DAY_LIGHT_FADE_LENGTH;
        end
    end

function findItemLightLevel()

    --do not count light from item we are holding
    if(client:getViewer():getUUID() == player:getUUID()) then
        return 0;
        end
    
    --otherwise, get items held
    item = client.getViewer():getHeldItem();
    offhandItem = client.getViewer():getHeldItem(true);

    itemEmittance = 0;
    offhandItemEmittance = 0;
    
    --then, if they're block items, get their blocks' respective light level
    if(item:isBlockItem()) then
        itemEmittance = item:getBlockstate():getLuminance();
        end
    if(offhandItem:isBlockItem()) then
        offhandItemEmittance = offhandItem:getBlockstate():getLuminance();
        end
    
    --return the maximum between the two light levels, normalized between 0-1
    return math.max(itemEmittance, offhandItemEmittance) / 15;
    end

--[[
This is the heart of this script. Theres a built in raycast in figura but it doesnt do exactly what we need it to,
so we have this one here instead.
Essentially, it gradually steps along, checking light levels to find the maximum along that ray.
It's a bit more complicated than that, but thats the basic idea.
]]--
function castEyeshineRay(startPos, stepVec)
    maxLightLevel = 0;
    --use i for number of steps looping until we reach a distance of CONFIG.DISTANCE
    startIndex = CONFIG.START_DISTANCE/CONFIG.STEP;
    endIndex = CONFIG.DISTANCE/CONFIG.STEP;
    i = startIndex;
    stepCount = 0;
    prevInst = avatar:getCurrentInstructions();
    if(CONFIG.BLOCK_LIGHT_ENABLED) then
        while i < endIndex do
            i = i + 1;
            stepCount = stepCount + 1;
            --Calculate the fall off. This is used to determine how far away from a light source will still allow eyes to shine.
            --It increases with distance to emulate the fact that distance from the ray shouldnt matter as much as angle.
            currentFallOff = CONFIG.FALL_OFF * i * CONFIG.STEP / CONFIG.FALL_OFF_DISTANCE;
            --Make sure fall off never goes above 14, or else eyeshine would always appear after a certain distance.
            currentFallOff = math.min(currentFallOff, 14);
            --If theres a solid block, at the current position, ray has hit a wall and we can exit. We also know that ray is not open sky, so we can set sky to false.
            if(world.getBlockState(startPos + i * stepVec):isOpaque()) then 
                sky = false; 
                break; 
                end
            if(avatar:getCurrentInstructions() - prevInst > avatar:getMaxTickCount() * CONFIG.MAX_INSTRUCTION_PROPORTION) then
                break;
                end
            lightLevelComparison = ((world.getBlockLightLevel(startPos + i * stepVec) - (15 - currentFallOff)) / currentFallOff - (maxLightLevel)) * 15
            nextLightLevelComparison = (world.getBlockLightLevel(startPos + (i + 1/CONFIG.STEP) * stepVec) - (15 - currentFallOff) - (maxLightLevel))

            --Since we use a more complicated algorithm to get the exact light level at a particular point, we use a simple check to determine if exact light level cannot possibly be a new maximum brightness.
            --This optimization seems to speed things up a lot.
            if(lightLevelComparison >= 0) then
                lightLevel = checkLightLevel(startPos + i * stepVec, currentFallOff);
                maxLightLevel = math.max(maxLightLevel, lightLevel);
                end
            if(lightLevelComparison <= -3) then
                i = i + 1 / CONFIG.STEP - 1;
                end
            end
        else
            while i < endIndex do
                i = i + 1 / CONFIG.STEP;
                stepCount = stepCount + 1;
                --Calculate the fall off. This is used to determine how far away from a light source will still allow eyes to shine.
                --It increases with distance to emulate the fact that distance from the ray shouldnt matter as much as angle.
                currentFallOff = CONFIG.FALL_OFF * i * CONFIG.STEP / CONFIG.FALL_OFF_DISTANCE;
                --Make sure fall off never goes above 14, or else eyeshine would always appear after a certain distance.
                currentFallOff = math.min(currentFallOff, 14);
                --If theres a solid block, at the current position, ray has hit a wall and we can exit. We also know that ray is not open sky, so we can set sky to false.
                if(world.getBlockState(startPos + i * stepVec):isOpaque()) then 
                    sky = false; 
                    break; 
                    end
                end
        end
    return maxLightLevel;
    end

--[[
Ok so. Checking the light level is kinda simple, but its hard to visualize.
Essentially, we take the light level of all the nearest blocks, and then use a series of linear interpolations (basically a weighted average) to calculate an exact light level at that point. (This is called trilinear interpolation)
.______.
|      |
|   x  |
|______|
so like, simplifying to 2d, imagine we have a point in between these four corners, which we know the light level of.
first, we calculate vertically what the light level of each point on the edges aligned with the middle point is, using linear interpolation

.______.
|      |
.   x  .
|______|

then, we can linearly interpolate again to find the exact light level at the center point

.______.
|      |
.___x__.
|______|

This generalizes to 3d pretty simply, calculating the four corners of a square first from the eight cube corners that aligns with the point in the third dimension.

]]--
function checkLightLevel(pos, fallOff)
    --So, the light level at each block is used as if that is the light level at the center of the block, but it is stored in the position at the corner of the block.
    --We have to subtract 0.5 in each direction to correct for this, then using that value to find the nearest blocks.
    bottomLeftBlock = vec(math.floor(pos.x-0.5), math.floor(pos.y-0.5), math.floor(pos.z-0.5));
    blockLightLevels = {
            world.getBlockLightLevel(bottomLeftBlock + vec(0,0,0)), world.getBlockLightLevel(bottomLeftBlock + vec(1,0,0)),
            world.getBlockLightLevel(bottomLeftBlock + vec(0,1,0)), world.getBlockLightLevel(bottomLeftBlock + vec(1,1,0)),
            world.getBlockLightLevel(bottomLeftBlock + vec(0,0,1)), world.getBlockLightLevel(bottomLeftBlock + vec(1,0,1)),
            world.getBlockLightLevel(bottomLeftBlock + vec(0,1,1)), world.getBlockLightLevel(bottomLeftBlock + vec(1,1,1))
    }
    centerLightLevel = world.getBlockLightLevel(pos);
    for i = 0, #(blockLightLevels) do
        if(blockLightLevels[i] == nil) then blockLightLevels[i] = centerLightLevel; end
        end
    --calculate the position within the 8 block centers
    subBlockPos = pos - bottomLeftBlock - vec(0.5,0.5,0.5);
    --calculate the square of light levels at the correct x position
    firstLerps = {
        math.lerp(blockLightLevels[1], blockLightLevels[2], subBlockPos.x), 
        math.lerp(blockLightLevels[3], blockLightLevels[4], subBlockPos.x),
        math.lerp(blockLightLevels[5], blockLightLevels[6], subBlockPos.x), 
        math.lerp(blockLightLevels[7], blockLightLevels[8], subBlockPos.x)
    }
    --calculate the exact light level
    trueLightLevel = math.lerp( 
                        math.lerp(firstLerps[1], firstLerps[2], subBlockPos.y),
                        math.lerp(firstLerps[3], firstLerps[4], subBlockPos.y),
                        subBlockPos.z);
    --normalize light level and account for fall off
    return (trueLightLevel - (15 - fallOff))/fallOff;
                        
    end