#include "PBRLightingPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, PBRLightingPass>();
}

PBRLightingPass::PBRLightingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpFbo = Fbo::create(mpDevice);
}

Properties PBRLightingPass::getProperties() const
{
    return {};
}

RenderPassReflection PBRLightingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection r;

    r.addInput("posW", "World-space position");
    r.addInput("normW", "World-space normal");
    r.addInput("emissive", "Emissive color");
    r.addInput("diffuseOpacity", "Diffuse reflectance and opacity");
    r.addInput("specRough", "Specular reflectance and roughness");

    // clang-format off
    r.addOutput("color", "Linear HDR lighting")
     .format(ResourceFormat::RGBA16Float)
     .bindFlags(ResourceBindFlags::RenderTarget);
    // clang-format on

    return r;
}

void PBRLightingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpLightingPass = nullptr;
}

void PBRLightingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto pColor = renderData.getTexture("color");
    mpFbo->attachColorTarget(pColor, 0);

    // Produce a defined black image even if no scene or shader is ready.
    pRenderContext->clearFbo(mpFbo.get(), float4(0.f, 0.f, 0.f, 1.f), 1.f, 0, FboAttachmentType::Color);

    if (!mpScene)
        return;

    // Recreate the program if compilation inputs change
    if (is_set(mpScene->getUpdates(), IScene::UpdateFlags::RecompileNeeded))
        mpLightingPass = nullptr;

    if (!mpLightingPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addTypeConformances(mpScene->getTypeConformances());

        desc.addShaderLibrary("RenderPasses/PBRLightingPass/PBRLightingPass.ps.slang").psEntry("psMain");

        mpLightingPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
    }

    // get var entry
    auto var = mpLightingPass->getRootVar();

    var["gPosW"] = renderData.getTexture("posW");
    var["gNormW"] = renderData.getTexture("normW");
    var["gDiffuseOpacity"] = renderData.getTexture("diffuseOpacity");
    var["gSpecRough"] = renderData.getTexture("specRough");
    var["gEmissive"] = renderData.getTexture("emissive");

    var["gUseEnvLight"] = mpScene->useEnvLight();
    var["gUseEnvBackground"] = mpScene->useEnvBackground();
    mpScene->bindShaderData(var["gScene"]);

    mpLightingPass->execute(pRenderContext, mpFbo);
}

void PBRLightingPass::renderUI(Gui::Widgets& widget) {}
