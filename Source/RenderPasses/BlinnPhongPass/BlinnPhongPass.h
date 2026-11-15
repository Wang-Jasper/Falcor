#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

// Forward-rendering reference: scene diffuse materials and uniform specular parameters.
class BlinnPhongPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(BlinnPhongPass, "BlinnPhongPass", "Forward Blinn-Phong lighting reference.");

    static ref<BlinnPhongPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<BlinnPhongPass>(pDevice, props);
    }

    BlinnPhongPass(ref<Device> pDevice, const Properties& props);

    RenderPassReflection reflect(const CompileData& compileData) override;
    void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    void execute(RenderContext* pRenderContext, const RenderData& renderData) override;

private:
    ref<Scene> mpScene;
    ref<GraphicsState> mpState;
    ref<Fbo> mpFbo;
    ref<Program> mpProgram;
    ref<ProgramVars> mpVars;
};
