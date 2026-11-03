import { useApp } from "../app-state"
import { Avatar } from "../components/Avatar"
import { Button } from "../components/Button"
import { Icon } from "../components/Icon"
import { Landing, Rise } from "../components/Landing"

export function Profile() {
  const { enterprise, go, setSheet, setStep } = useApp()
  return (
    <Landing id="Profile" once>
      <Rise className="page-heading" index={0}>
        <h2>Your space</h2>
      </Rise>
      <div className="page-content profile">
        <Avatar name="Alex Morgan" photo />
        <h2>Alex Morgan</h2>
        <p>Connectum ID · MN68-2CQ9</p>
        {[
          enterprise,
          "Set a password",
          "Experience the introduction",
          "Sign out",
        ].map((x, i) => (
          <Button
            key={x}
            landing={1 + i}
            className="setting"
            onClick={() =>
              x === "Experience the introduction"
                ? (setStep(0), go("Onboarding"))
                : setSheet(x)
            }
          >
            {x}
            <Icon name="arrow" />
          </Button>
        ))}
      </div>
    </Landing>
  )
}
