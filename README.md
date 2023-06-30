# Nishita Sky With Volumetric Clouds

This is a Nishita sky shader for Godot 4.0, with [Clay John's volumetric clouds](https://github.com/clayjohn/godot-volumetric-cloud-demo) based on [a tutorial by scratch pixel](https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds/simulating-sky/simulating-colors-of-the-sky.html).

## Screenshots

| ![Day](Screenshots/1%20day.webp) | ![Sunset](Screenshots/2%20sunset.webp) |
| --- | --- |
| Day | Sunset |

| ![Cloudy Sky](Screenshots/3%20cloudy%20sky.webp) | ![Partial Eclipse](Screenshots/4%20partial%20eclipse.webp) |
| --- | --- |
| Cloudy Sky | Partial Eclipse |

| ![Full Eclipse](Screenshots/5%20full%20eclipse.webp) | ![Blood Moon](Screenshots/6%20blood%20moon.webp) |
| --- | --- |
| Full Eclipse | Blood Moon |

| ![Night Sky](Screenshots/7%20night%20sky%20with%20clouds.webp) | ![Night Sky Without Clouds](Screenshots/8%20night%20sky%20without%20clouds.webp) |
| --- | --- |
| Night Sky | Night Sky Without Clouds |

| ![Earth From Above](Screenshots/9%20earth%20from%20above.webp) | ![Earth From Above Sunset](Screenshots/10%20earth%20from%20above%20sunset.webp) |
| --- | --- |
| Earth From Above | Earth From Above Sunset |

## Features
* Game-ready asset
* Raymarched sky
* Raymarched clouds that move with the camera
* Different times of day by rotating the "NishitaSky" node
* Realistic lighting at different altitudes
* A night sky, with Milky Way texture
* A directional light that takes on the color of the sun in the shader
* All elements interact with each other: the night sky is blocked by the clouds and attenuated by the atmosphere
* Ability to configure quality of the shader and turn the clouds on/off
* Moon
    * Realistically lit moon influenced by the sun, resulting in different moon phases, including Earth blocking moon (new moon phase, and blood moon)
* Support for moon and ground textures, accurate textures included
* Performance optimizations

## Bonus Features
* Raising the camera high on the Y axis brings the moon closer
* Moving the camera on the XZ axis (very far) changes the sky and ground texture position

## Limitations
* Performance heavy, especially with clouds on
* The camera must remain below the clouds (but is clamped to cloud height if it goes higher), since the clouds do not actually exist

## Improvements
* For the sky precompute the optical depth between the sun and an arbitrary point along the ray (from Nishita's paper)
* Add multiple scattering to clouds and sky
* Physical raytraced clouds, with better lighting (currently the clouds are evenly lit)
* Better cloud density textures
* Use cloud sample distance for cloud fog (currently uses distance to clouds)
* Physically accurate ground material (currently the brightness is just a dot product to the sun)
* Better sun color saturation (currently some hacks are necessary to get the expected sun brightness and saturation)

## How to Use
To implement this sky into a project
1. Copy the "NishitaSky" node from the main scene into the project
2. In the "NishitaSky" node set "sun_object_path" variable to the desired directional light, do not make this directional light a child of the "NishitaSky" node
3. Create an "WorldEnvironment" node, set the sky material to the "nishita_sky" material
4. Click copy on the sky section of the "WorldEnvironment" node, and paste it into the "sky_material" section of the "NishitaSky" node. **THE MATERIALS MUST BE LINKED FOR THE SKY PARAMETERS TO BE THE SAME ON THE SCRIPT AND THE SHADER**
5. Set the correct "sun_ground_height" on the "NishitaSky" node, this is the height of objects on the ground
6. After adjusting all settings as needed click the "Compute Gradient Toggle" to precompute the sun color gradient
7. It may be necessary to reload the scene to make the sky work in the editor
8. If the sky is very slow try changing the process mode to "High-Quality Incremental" in the Sky settings in the WorldEnvironment

To understand what the shader settings do, read the comments in the `nishita_sky.gdshader` file.
The variables prefixed with `precomputed_` are set by the `NishitaSky.gd` script, they cannot be modified.

## Todo
* Fix clouds "jumping" after some time
* Clean up code
* Rework sun saturation
* Set WorldEnvironment fog color based on sky color
* Make stars move with the sun
    * Position sun, stars, and moon using a real world date/time

## Images
* Moon albedo was rendered from [NASA](https://svs.gsfc.nasa.gov/cgi-bin/details.cgi?aid=4720)
* Night sky HDRI was underexposed and compressed to webp from [NASA](https://svs.gsfc.nasa.gov/4851#media_group_5169)
* Earth image was color corrected and compressed to webp from [NASA](https://visibleearth.nasa.gov/images/74142/september-blue-marble-next-generation/74159l)
