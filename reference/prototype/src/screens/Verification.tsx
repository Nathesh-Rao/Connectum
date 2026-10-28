import { useApp } from "../app-state"
import { AccessForm } from "../components/AccessForm"

export function Verification() {
  const { email, setEmail, go } = useApp()
  return (
    <AccessForm
      verification
      email={email}
      setEmail={setEmail}
      onBack={() => go("Authentication")}
      onContinue={() => go("Enterprises")}
    />
  )
}
