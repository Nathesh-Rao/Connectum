// A yes/no value: green "Yes" or red "No" pill with a dot. These semantic
// colors are the only color on a submission card besides its left border.
export function YesNo({ value }: { value: string }) {
  const yes = value === "Yes"
  return (
    <span className={"yn " + (yes ? "yes" : "no")}>
      <i />
      {yes ? "Yes" : "No"}
    </span>
  )
}
