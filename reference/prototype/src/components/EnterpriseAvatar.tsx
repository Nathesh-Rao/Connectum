import { Icon } from "./Icon"

export function EnterpriseAvatar({ index }: { index: number }) {
  return (
    <span
      className={`enterprise-avatar enterprise-avatar-${index}`}
      aria-hidden="true"
    >
      <Icon
        name={
          ["building", "briefcase", "people", "university", "hospital"][
            index
          ] || "building"
        }
      />
    </span>
  )
}
