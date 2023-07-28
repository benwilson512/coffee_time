// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  darkMode: 'class',
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        // coffee cup https://www.schemecolor.com/coffee-cup.php
        'dark-gold': "#9F683A",
        'milk-chocolate': "#7F5234",
        'pastel-gray': {
          'DEFAULT': "#DACFBF",
          '100': "#DED4C5",
          '200': "#E1D9CC",
          '300': "#E5DDD2",
          '400': "#E9E2D9",
          '500': "#EDE7DF",
          '600': "#F0ECE5",
          '700': "#F4F1EC",
          '800': "#F8F5F2",
          '900': "#FBFAF9",
        },
        'cafe-noir': "#51331F",
        'grullo': "#AC8D83",
        'dark-chestnut': "#8B6B62",
        // ristretto https://www.schemecolor.com/ristretto.php
        'root-beer': '#1F0E04',
        'black-bean': '#431307',
        'citrine-brown': '#932C0D',
        'very-pale-orange': '#FCE4BE',
        'cadmium-orange': '#ED7B35',
        // romantic https://www.schemecolor.com/romantic-coffee-color-scheme.php
        'dark-brown-tangelo': "#8B6748",
        'crayolas-gold': '#ECBA9C',
        'tumbleweed': '#E6B08D',
        'royal-brown': '#56382B',
        'salmon': '#F48472',
        'jelly-bean': '#DE5F46',
        // aliases
        brand: "#DE5F46"
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "./vendor/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).map(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) }
        })
      })
      matchComponents({
        "hero": ({ name, fullPath }) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": theme("spacing.5"),
            "height": theme("spacing.5")
          }
        }
      }, { values })
    })
  ]
}
