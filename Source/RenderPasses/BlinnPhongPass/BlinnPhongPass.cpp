#include "BlinnPhongPass.h"

// The vertex and pixel shader entries share this shader file.
namespace
{
const char kShaderFile[] = "RenderPasses/BlinnPhongPass/BlinnPhong.3d.slang";
}

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, BlinnPhongPass>();
}

BlinnPhongPass::BlinnPhongPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Reusable containers for graphics state and framebuffer attachments.
    mpState = GraphicsState::create(mpDevice);
    mpFbo = Fbo::create(mpDevice);

    // Opaque geometry: test depth and write the closest visible surface.
    DepthStencilState::Desc depthDesc;
    depthDesc.setDepthEnabled(true).setDepthFunc(ComparisonFunc::LessEqual).setDepthWriteMask(true);
    mpState->setDepthStencilState(DepthStencilState::create(depthDesc));
}

RenderPassReflection BlinnPhongPass::reflect(const CompileData& compileData)
{
    RenderPassReflection r;

    // Forward shading writes directly to the color attachment; no G-buffer inputs.
    // Dimensions default to the RenderGraph's texture dimensions.
    r.addOutput("color", "Linear HDR lighting")
        .format(ResourceFormat::RGBA16Float)
        .bindFlags(ResourceBindFlags::RenderTarget);

    r.addOutput("depth", "Scene depth")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::DepthStencil);

    return r;
}

void BlinnPhongPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    // Scene-dependent shader modules and defines may have changed.
    mpProgram = nullptr;
    mpVars = nullptr;
}

void BlinnPhongPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    // 1. Attach the RenderGraph-owned output textures.
    mpFbo->attachColorTarget(renderData.getTexture("color"), 0);
    mpFbo->attachDepthStencilTarget(renderData.getTexture("depth"));
    mpState->setFbo(mpFbo);

    // 2. Clear every frame, including when no scene is loaded.
    pRenderContext->clearFbo(
        mpFbo.get(), float4(0.f, 0.f, 0.f, 1.f), 1.f, 0,
        FboAttachmentType::Color | FboAttachmentType::Depth
    );

    if (!mpScene)
        return;

    if (is_set(mpScene->getUpdates(), IScene::UpdateFlags::RecompileNeeded))
    {
        mpProgram = nullptr;
        mpVars = nullptr;
    }

    // 3. Create the vertex/pixel shader program once, then reuse it.
    if (!mpProgram)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addTypeConformances(mpScene->getTypeConformances());
        desc.addShaderLibrary(kShaderFile).vsEntry("vsMain").psEntry("psMain");

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
        mpState->setProgram(mpProgram);
    }

    // 4. Bind the shared shininess exponent; light and reflectance data come from gScene.
    auto cb = mpVars->getRootVar()["PerFrameCB"];
    cb["gShininess"] = 32.f;

    // 5. Falcor binds gScene (including the camera) and draws scene geometry.
    // The pixel shader evaluates Blinn-Phong and writes the HDR color attachment.
    mpScene->rasterize(pRenderContext, mpState.get(), mpVars.get(), RasterizerState::CullMode::Back);
}
