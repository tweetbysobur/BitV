import { describe, expect, it } from "vitest";
import { deriveCVALabel, CVA_RECOGNITION_DISCLAIMER } from "@/lib/cva";
import { deriveCVIStatus } from "@/lib/cvi";

describe("CVA status separation from CVI", () => {
  it("keeps adminAttestedCVA and interfaceVerified as fully independent inputs", () => {
    expect(deriveCVALabel({ adminAttestedCVA: false, interfaceVerified: false })).toBe(
      "Not attested as CVA",
    );
    expect(deriveCVALabel({ adminAttestedCVA: true, interfaceVerified: false })).toBe(
      "Admin attested — interface not verified",
    );
    expect(deriveCVALabel({ adminAttestedCVA: false, interfaceVerified: true })).toBe(
      "Interface verified — not admin attested",
    );
    expect(deriveCVALabel({ adminAttestedCVA: true, interfaceVerified: true })).toBe(
      "Fully recognized (BitV verification only)",
    );
  });

  it("never claims Cleanverse approval in any label", () => {
    const labels = [
      deriveCVALabel({ adminAttestedCVA: false, interfaceVerified: false }),
      deriveCVALabel({ adminAttestedCVA: true, interfaceVerified: false }),
      deriveCVALabel({ adminAttestedCVA: false, interfaceVerified: true }),
      deriveCVALabel({ adminAttestedCVA: true, interfaceVerified: true }),
    ];
    for (const label of labels) {
      expect(label.toLowerCase()).not.toContain("cleanverse approved");
      expect(label.toLowerCase()).not.toContain("approved");
    }
    expect(CVA_RECOGNITION_DISCLAIMER).toContain("does not confirm Cleanverse has approved");
  });

  it("CVI and CVA modules are independently derivable and do not merge", () => {
    // A fully-recognized CVA asset must not make an unverified wallet
    // appear CVI-compliant, and vice versa — the two modules never
    // read from each other.
    const cva = deriveCVALabel({ adminAttestedCVA: true, interfaceVerified: true });
    const cvi = deriveCVIStatus({
      walletConnected: true,
      validatorConfigured: true,
      complianceVerifyResult: false,
      readError: false,
    });
    expect(cva).toBe("Fully recognized (BitV verification only)");
    expect(cvi).toBe("not-verified");
  });
});
