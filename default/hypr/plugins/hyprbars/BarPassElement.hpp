#pragma once
#include <hyprland/src/render/pass/PassElement.hpp>

class CHyprBar;

class CBarPassElement : public IPassElement {
  public:
    struct SBarData {
        CHyprBar* deco = nullptr;
        float     a    = 1.F;
    };

    CBarPassElement(const SBarData& data_);
    virtual ~CBarPassElement() = default;

    virtual std::vector<UP<IPassElement>> draw() override;
    virtual bool                          needsLiveBlur() override;
    virtual bool                          needsPrecomputeBlur() override;
    virtual std::optional<CBox>           boundingBox() override;

    virtual const char*                   passName() override {
        return "CBarPassElement";
    }

    virtual ePassElementType type() override {
        return EK_CUSTOM;
    }

  private:
    SBarData data;
};