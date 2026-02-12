import { Workflow, smithers } from "./smithers-audit";
import { Audit } from "./components/Audit";

export default smithers(() => {
  return (
    <Workflow name="smithers-v2-audit">
      <Audit />
    </Workflow>
  );
});
