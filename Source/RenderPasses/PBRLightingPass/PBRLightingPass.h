#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "Core/Pass/FullScreenPass.h"

using namespace Falcor;

class PBRLightingPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(PBRLightingPass, "PBRLightingPass", "Deferred PBR lighting pass.");

    static ref<PBRLightingPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<PBRLightingPass>(pDevice, props); }

    PBRLightingPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ref<Scene> mpScene;         // scene reference
    ref<Fbo> mpFbo;             // FrameBufferObeject
    ref<FullScreenPass> mpLightingPass; // Fullscreen shader program, parameters, and graphics state.
};
