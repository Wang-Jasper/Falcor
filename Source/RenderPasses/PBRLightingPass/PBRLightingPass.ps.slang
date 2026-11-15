import Scene.Shading;
import Rendering.Lights.LightHelpers;
import Rendering.Materials.IsotropicGGX;
import Utils.Math.MathHelpers;
import Utils.Sampling.LowDiscrepancy.HammersleySequence;
#include "Utils/Math/MathConstants.slangh"

Texture2D<float4> gPosW;
Texture2D<float4> gNormW;
Texture2D<float4> gDiffuseOpacity;
Texture2D<float4> gSpecRough;
Texture2D<float4> gEmissive;
uniform bool gUseEnvLight;      // env light illuminates object
uniform bool gUseEnvBackground; // show envbackground in empty pixel

/*
 L_0 = L_i * (f_diffuse + f_specular) * max(dot(N, L), 0)

 f_diffuse = (1 - F)diffuseReflectance / pi
 f_specular = ( D * F * G ) / 4 ( N dot L * N dot V )
 alpha = roughness^2
 D = alpha^2 / (pi * ((N dot H)^2 * (alpha^2 - 1) + 1)^2) - How many microfaces can participate in specular reflection
 F = F0 + (1 - F0) * (1 - (V dot H))^5 - how many energy is reflected by the microfaces

 k = (roughness + 1)^2 / 8
 G1(x) = x / (x * (1 - k) + k)
 G = G1(max(dot(N, L), 0)) * G1(max(dot(N, V), 0)) - how many microfaces are visible to the light and the view direction
*/

float3 sampleDiffuseDirectionLocal(uint sampleIndex, uint sampleCount)
{
    float u = (float(sampleIndex) + 0.5f) / float(sampleCount);
    float v = radicalInverse(sampleIndex);
    return sample_cosine_hemisphere_polar(float2(u, v));
}

float3 evalFilteredEnvMap(float3 direction, float sampleSolidAngle, float2 envDim)
{
    float2 uv = gScene.envMap.worldToUv(direction);

    float halfTexelHeight = 0.5f / envDim.y;
    float latitudeV = clamp(uv.y, halfTexelHeight, 1.f - halfTexelHeight);
    float texelSolidAngle = M_2PI * M_PI * sin(M_PI * latitudeV) / (envDim.x * envDim.y);
    float lod = max(0.f, 0.5f * log2(sampleSolidAngle / texelSolidAngle));
    return gScene.envMap.eval(uv, lod);
}

// FullScreenPass supplies the vertex shader. Select this entry using psEntry("psMain").
float4 psMain(float2 texC: TEXCOORD, float4 posH: SV_Position)
    : SV_Target0
{
    uint2 pixel = uint2(posH.xy); // getting the center of the current processing pixel

    // getting world pos
    float4 position = gPosW.Load(int3(pixel, 0));
    if (position.w == 0.f) // inifite distance - no object
    {
        if (gUseEnvBackground)
        {
            uint2 frameDim;
            gPosW.GetDimensions(frameDim.x, frameDim.y);                          // read frame size from g-buffer
            float3 rayDir = gScene.camera.computeRayPinhole(pixel, frameDim).dir; // a ray from the camera through the current pixel (with camera jittering applied)
            return float4(gScene.envMap.eval(rayDir), 1.f);                       // return the background color from the environment map
        }
        return float4(0.f, 0.f, 0.f, 1.f); // if no environment background, return black for the pixel
    }
    float3 posW = position.xyz;
    float3 diffuseReflectance = gDiffuseOpacity.Load(int3(pixel, 0)).rgb; // the percentage of energy is reflected by the surface by each RGB channel
    float4 specRough = gSpecRough.Load(int3(pixel, 0));
    float3 F0 = specRough.rgb;                        // specular reflectance at normal
    float roughness = clamp(specRough.a, 0.04f, 1.f); // Avoid the singularity at zero roughness.

    float3 N = normalize(gNormW.Load(int3(pixel, 0)).xyz);
    float3 V = normalize(gScene.camera.getPosition() - posW);

    // add self emission first
    float3 color = gEmissive.Load(int3(pixel, 0)).rgb;
    float NdotV = dot(N, V);
    if (NdotV > 0.f) // only consider the front face of the surface
    {
        for (uint lightIndex = 0; lightIndex < gScene.getLightCount(); ++lightIndex)
        {
            AnalyticLightSample lightSample;
            if (!evalLightApproximate(posW, gScene.getLight(lightIndex), lightSample))
                continue;

            float3 L = lightSample.dir;
            float NdotL = max(dot(N, L), 0.f);
            if (NdotL <= 0.f) // when light is behind the surface
                continue;
            float3 H = normalize(L + V); // ommit the case of L and V are opposite

            float3 F = F0 + (1.f - F0) * pow(1.f - max(dot(V, H), 0.f), 5.f);
            float3 f_diffuse = (1.f - F) * diffuseReflectance * M_1_PI;
            float alpha = roughness * roughness;
            float alpha2 = alpha * alpha;
            float NdotH = max(dot(N, H), 0.f);
            float term = NdotH * NdotH * (alpha2 - 1.f) + 1.f;
            float3 D = float3(alpha2 * M_1_PI / max(term * term, 1e-12f));
            float k = pow(roughness + 1.f, 2) / 8.f;
            float3 G = (max(dot(N, L), 0.f) / (max(dot(N, L), 0.f) * (1.f - k) + k)) * float3(max(dot(N, V), 0.f) / (max(dot(N, V), 0.f) * (1.f - k) + k));

            float3 f_specular = (D * F * G) / (4.f * max(dot(N, L), 0.f) * max(dot(N, V), 0.f));

            color += lightSample.Li * (f_diffuse + f_specular) * NdotL;
        }
    }

    if (gUseEnvLight) // calculate the contribution of the environment light
    {
        // DIFFUSE
        float2 envDim = float2(gScene.envMap.getDimensions()); // size of environment map in pixels
        float3 T, B;                                           // Tangent and Bitangent vectors for the local coordinate system
        branchlessONB(N, T, B);                                // N as local +Z, T as local +X, B as local +Y.

        const uint sampleCount = 32; // use 32 samples for diffuse reflection
        float3 sumLi = 0.f;          // sum for diffuse reflect
        for (uint sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex)
        {
            float3 localDir = sampleDiffuseDirectionLocal(sampleIndex, sampleCount); // dir from coloring point to a weighted direction
            float3 L = localDir.x * T + localDir.y * B + localDir.z * N;             // to world space
            float pdf = localDir.z * M_1_PI;                                         // cos(theta) / pi - theta = N * L
            float sampleSolidAngle = 1.f / (float(sampleCount) * pdf);               // estimate the coverage solid angle of current sample
            sumLi += evalFilteredEnvMap(L, sampleSolidAngle, envDim);
        }

        // get average of the diffuse reflection from the environment light and multiply by the diffuse reflectance
        color += diffuseReflectance * (sumLi / float(sampleCount));

        // SPECULAR
        if (NdotV > 0.f) // light in front face of the surface
        {
            const uint specularSampleCount = 64;
            float alpha = roughness * roughness;
            float3 specularSum = 0.f;

            for (uint i = 0; i < specularSampleCount; ++i)
            {
                float2 u = getHammersley(i, specularSampleCount);

                float pdfH;
                float3 localH = sampleGGX_NDF(alpha, u, pdfH);
                float3 H = localH.x * T + localH.y * B + localH.z * N;

                float VdotH = saturate(dot(V, H));
                if (VdotH <= 0.f)
                    continue;

                float3 L = reflect(-V, H);
                float NdotL = saturate(dot(N, L));
                if (NdotL <= 0.f)
                    continue;

                float D = evalNdfGGX(alpha, localH.z);
                float3 F = F0 + (1.f - F0) * pow(1.f - VdotH, 5.f);
                float G = evalMaskingSmithGGXCorrelated(alpha, NdotL, NdotV);

                float3 fSpecular = D * F * G / (4.f * NdotL * NdotV);
                float pdfL = pdfH / (4.f * VdotH);
                float sampleSolidAngle = 1.f / (float(specularSampleCount) * pdfL);
                float3 Li = evalFilteredEnvMap(L, sampleSolidAngle, envDim);
                specularSum += Li * fSpecular * NdotL / pdfL;
            }

            color += specularSum / float(specularSampleCount);
        }
    }

    return float4(color, 1.f);
}
