# Nishita Sky With Volumetric Clouds

This is a Nishita sky shader for godot 4.0, with [Clay John's volumetric clouds](https://github.com/clayjohn/godot-volumetric-cloud-demo) based on [a tutorial by scratch pixel](https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds/simulating-sky/simulating-colors-of-the-sky.html), which is recommended to read to understand what the sky parameters represent, when configuring the sky.

## Screenshots (stars amplified for demonstration purposes)

**Day**
![day](Screenshots/day.png)

**Day Without Clouds**
![day without clouds](Screenshots/day%20without%20clouds.png)

**High Quality Day**
![high quality day](Screenshots/high%20quality%20day.png)

**Sunset**
![sunset](Screenshots/sunset.png)

**After Sunset**
![after sunset](Screenshots/after%20sunset.png)

**Cloudy Night Sky After Sunset**
![cloudy night sky after sunset](Screenshots/cloudy%20night%20sky%20after%20sunset.png)

**Cloudy Night Sky**
![cloudy night sky](Screenshots/cloudy%20night%20sky.png)

**Atmosphere from 100km**
![atmosphere from 100km](Screenshots/atmosphere%20from%20100km.png)

**Low Sun Atmosphere from 100km**
![low sun atmosphere from 100km](Screenshots/low%20sun%20atmosphere%20from%20100km.png)

**Very Low Sun Atmosphere From 100km**
![very low sun atmosphere from 100km](Screenshots/very%20low%20sun%20atmosphere%20from%20100km.png)

## Features
* Game-ready asset (although in alpha)
* Raymarched sky
* Raymarched clouds that move with the camera
* Different times of day by rotating the "NishitaSky" node
* Realistic lighting at different altitudes
* A night sky
* A directional light that takes on the color of the sun in the shader
* All elements interact with each other: the night sky is blocked by the clouds and attenuated by the atmosphere
* Ability to configure quality of the shader and turn the clouds on/off
* Performance optimizations

## Limitations
* Performance heavy, especially with clouds on
* The camera must remain below the clouds (but is clamped to cloud height if it goes higher), since the clouds do not actully exist

## Improvements
* For the sky precompute the optical depth between the sun and an arbitrary point along the ray (from Nishita's paper)
* Add multiple scattering to clouds and sky
* Physical raytraced clouds, with better lighting (curently the clouds are evenly lit)
* Better cloud density textures
* Use cloud sample distance for cloud fog (currently uses distance to clouds)
* Physically accurate ground material (currently the brightness is just a dot product to the sun)
* Better sun color saturation (currently some hacks are nessary to get the expected sun brightness and saturation)

## How to Use
To implement this sky into a project
1. Copy the "NishitaSky" node from the main scene into a the project
2. In the "NishitaSky" node set "sun_object_path" variable to the desired directional light, do not make this directional light a child of the "NishitaSky" node
3. Create an "WorldEnvironment" node, set the sky material to the "nishita_sky" material
4. Click copy on the sky section of the "WorldEnvironment" node, and paste it into the "sky_material" section of the "NishitaSky" node. **THE MATERIALS MUST BE LINKED FOR THE SKY PARAMETERS TO BE THE SAME ON THE SCRIPT AND THE SHADER**
5. Set the correct "sun_ground_height" on the "NishitaSky" node, this is the height of objects on the ground
6. After adjusting all settings as needed click the "Compute Gradient Toggle" to precompute the sun color gradient
7. It may be necessary to reload the scene to make the sky work in the editor
8. If the sky is very slow try changing the process mode to "High-Quality Incremental" in the Sky settings in the WorldEnvironment

## Todo
* Fix clouds "jumping" after some time
* Clean up code
* Rework sun saturation
* Set WorldEnvironment fog color based on sky color
