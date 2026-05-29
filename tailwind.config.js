/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./ucode/**/*.ut",
    "./htdocs/luci-static/resources/*.js",
    "./htdocs/**/*.html",
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        surface: "#18181b",
        muted: "#27272a",
        "muted-fg": "#a1a1aa",
        border: "rgba(255,255,255,0.06)",
        "border-strong": "rgba(255,255,255,0.1)",
        primary: "var(--primary, #5e72e4)",
      },
      fontFamily: {
        sans: ['"Google Sans"', '"Microsoft Yahei"', '"WenQuanYi Micro Hei"', "sans-serif"],
        logo: ["TypoGraphica"],
      },
      animation: {
        "fade-in": "fadeIn 0.4s ease-out",
      },
      keyframes: {
        fadeIn: {
          "0%": { opacity: "0", transform: "translateY(12px) scale(0.98)" },
          "100%": { opacity: "1", transform: "translateY(0) scale(1)" },
        },
      },
    },
  },
  plugins: [],
};
