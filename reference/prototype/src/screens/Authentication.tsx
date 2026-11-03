import { useApp } from "../app-state"
import { AccessForm } from "../components/AccessForm"

export function Authentication() {
  const { email, setEmail, go } = useApp()
  return (
    <AccessForm
      verification={false}
      email={email}
      setEmail={setEmail}
      onBack={() => go("Authentication")}
      onContinue={() => go("Verification")}
    />
  )
}
