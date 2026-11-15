import Scene.Raster;
import Rendering.Materials.TexLODHelpers;
import Rendering.Lights.LightHelpers;

// constant buffer: set by execute() in via mpVars with the same name.
cbuffer PerFrameCB
{
    float gShininess; // Blinn–Phong Highlight Exponent
};

// Vertex shader, each call processes one input vertex
VSOut vsMain(VSIn vsIn) // vsIn means vertext shader input, VSOut means vertex shader output
{
    return defaultVS(vsIn); // using falcor vertext shader
}

// Pixel Shader / Fragment Shader - TriangleIndex is provided by SV_PrimitiveID, which identifies the primitive in the current draw call.
float4 psMain(VSOut vsOut, uint triangleIndex: SV_PrimitiveID)
    : SV_Target0 // output write to FBO 0
{
    float3 N = normalize(vsOut.normalW);                            // world space normalized(after Interpolation) norm
    float3 V = normalize(gScene.camera.getPosition() - vsOut.posW); // inverse eye ray (from surface to camera)
    
    ShadingData sd = prepareShadingData(vsOut, triangleIndex, V); // know which world position, normal, uv, triangle index, view direction
    let lod = ImplicitLodTextureSampler();                        // create a texture sampler with implicit LOD selection; the sampler will automatically choose the appropriate mip level based on the pixel shader derivatives(near pixel if have big derivatives, means the pixels are far)
    let mi = gScene.materials.getMaterialInstance(sd, lod, 0);    // find the right material instance for the current surface;
    let properties = mi.getProperties(sd);                        // get the material properties for the current surface, including diffuse reflection albedo, specular reflectance, roughness, emission, etc

    // add self emission first
    float3 color = properties.emission;
    // find the active explicit lights in the scene;
    for (uint lightIndex = 0; lightIndex < gScene.getLightCount(); ++lightIndex)
    {
        AnalyticLightSample lightSample;                                                 // used to store current light evaluation result: direction, distance, incident light, etc.
        if (!evalLightApproximate(vsOut.posW, gScene.getLight(lightIndex), lightSample)) // get direction from surface to light, distance, intensity
            continue;                                                                    // only directional light and point light are supported

        float3 L = lightSample.dir;        // surface to light direction
        float NdotL = max(dot(N, L), 0.f); // cos of the angle between surface norm and light dir, 0 means light is behind the surface
        if (NdotL <= 0.f)                  // light is behind, skip
            continue;

        float3 diffuse = properties.diffuseReflectionAlbedo * NdotL; // diffuse reflection = diffuse albedo * cos(theta)
        float3 specular = float3(0.f);                               // set black specular first
        float3 halfVector = L + V;
        float lengthSquared = dot(halfVector, halfVector); // lengthSquared = |L + V|^2, used to normalize(prevent divide by 0)
        if (lengthSquared > 1e-8f)                         // not opposite
        {
            float3 H = halfVector * rsqrt(lengthSquared); // rsqrt(x) = 1 / sqrt(x), normalize
            float NdotH = max(dot(N, H), 0.f);            // cos of h, n
            specular = properties.specularReflectance * pow(NdotH, gShininess);
        }

        // Li is the intensity of the light source, RGB channel
        color += lightSample.Li * (diffuse + specular);
    }

    return float4(color, 1.f);
}
