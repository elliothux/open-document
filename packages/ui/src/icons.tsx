/** Selected GenOffice glyphs, 5eab98adc8d0ebf6ecea687e42400a791ef58d64.
 * Copyright 2026 Mainfunc, Inc.; Apache-2.0. */
export function Icon({
  name,
}: {
  name: "copy" | "cut" | "paste" | "undo" | "redo";
}) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {name === "copy" && (
        <>
          <rect x="7" y="7" width="14" height="14" rx="3" />
          <path d="M14.5 4H7C5.34 4 4 5.34 4 7v7.5" />
        </>
      )}
      {name === "cut" && (
        <>
          <path d="M7.91 19.27l1.01-1.7L16.98 3.59M7.02 3.5l8.06 13.97 1.01 1.8" />
          <circle cx="5.83" cy="18.13" r="2.37" />
          <circle cx="18.17" cy="18.13" r="2.37" />
        </>
      )}
      {name === "paste" && (
        <>
          <path d="M8.14 18.16H5.89C4.85 18.16 4 17.31 4 16.26V6.79C4 5.74 4.85 4.89 5.89 4.89h1.43M17.26 7.74v-.95c0-1.05-.85-1.9-1.89-1.9h-1.42" />
          <rect x="7.79" y="3" width="5.68" height="2.84" rx="0.95" />
          <path d="M18.21 7.74H9.68c-1.04 0-1.89.85-1.89 1.89v9.48c0 1.04.85 1.89 1.89 1.89h5.81l4.62-4.97v-6.4c0-1.04-.85-1.89-1.9-1.89zM10.63 11.05h6.63M10.63 14.37h3.79M15.37 21v-4.26c0-.53.42-.95.95-.95h3.79" />
        </>
      )}
      {name === "undo" && (
        <>
          <path d="M5.91026 4L2.5 7.14791L5.91026 10.8205" />
          <path d="M3.96154 7.41028H15.1636C18.5169 7.41028 21.3646 10.1484 21.4953 13.5C21.6334 17.0416 18.707 20.0769 15.1636 20.0769H6.88384" />
        </>
      )}
      {name === "redo" && (
        <>
          <path d="M18.0897 4L21.5 7.14791L18.0897 10.8205" />
          <path d="M20.0385 7.41028H8.83636C5.4831 7.41028 2.63537 10.1484 2.5047 13.5C2.36657 17.0416 5.29296 20.0769 8.83636 20.0769H17.1162" />
        </>
      )}
    </svg>
  );
}
