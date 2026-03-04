export interface Theme {
  name: string;
  background: string;
  text: string;
  secondaryText: string;
  icon: string;
  syntax: string;
  codeBackground: string;
  blockquote: string;
  link: string;
  checkbox: string;
  checked: string;
  hr: string;
  wikiLink: string;
  wikiLinkMissing: string;
  tag: string;
  tagBackground: string;
  cursor: string;
  sidebarBackground: string;
  sidebarHover: string;
  sidebarActive: string;
  border: string;
}

// Helper to convert RGB values to hex/rgb strings
const rgb = (r: number, g: number, b: number, a: number = 1): string => {
  if (a === 1) {
    const toHex = (n: number) => Math.round(n * 255).toString(16).padStart(2, '0');
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  }
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a})`;
};

export const darkTheme: Theme = {
  name: 'Dark',
  background: rgb(0.1, 0.1, 0.1),
  text: rgb(1, 1, 1),
  secondaryText: rgb(0.6, 0.6, 0.6),
  icon: rgb(0.85, 0.85, 0.85),
  syntax: rgb(1, 1, 1, 0.3),
  codeBackground: rgb(1, 1, 1, 0.1),
  blockquote: rgb(0.7, 0.7, 0.8),
  link: rgb(0.49, 0.30, 1.0),
  checkbox: rgb(0.4, 0.8, 0.4),
  checked: rgb(0.5, 0.5, 0.5),
  hr: rgb(1, 1, 1, 0.4),
  wikiLink: rgb(0.3, 0.7, 0.9),
  wikiLinkMissing: rgb(0.7, 0.5, 0.3),
  tag: rgb(0.4, 0.75, 0.6),
  tagBackground: rgb(0.4, 0.75, 0.6, 0.15),
  cursor: rgb(1, 1, 1),
  sidebarBackground: rgb(0.08, 0.08, 0.08),
  sidebarHover: rgb(0.15, 0.15, 0.15),
  sidebarActive: rgb(0.2, 0.2, 0.25),
  border: rgb(0.3, 0.3, 0.3),
};

export const lightTheme: Theme = {
  name: 'Light',
  background: rgb(0.98, 0.98, 0.98),
  text: rgb(0.1, 0.1, 0.1),
  secondaryText: rgb(0.45, 0.45, 0.45),
  icon: rgb(0.3, 0.3, 0.3),
  syntax: rgb(0.4, 0.4, 0.4, 0.6),
  codeBackground: rgb(0, 0, 0, 0.06),
  blockquote: rgb(0.35, 0.35, 0.45),
  link: rgb(0.15, 0.1, 0.75),
  checkbox: rgb(0.15, 0.55, 0.15),
  checked: rgb(0.5, 0.5, 0.5),
  hr: rgb(0, 0, 0, 0.35),
  wikiLink: rgb(0.05, 0.45, 0.65),
  wikiLinkMissing: rgb(0.55, 0.35, 0.15),
  tag: rgb(0.15, 0.5, 0.35),
  tagBackground: rgb(0.15, 0.5, 0.35, 0.15),
  cursor: rgb(0.15, 0.15, 0.15),
  sidebarBackground: rgb(0.95, 0.95, 0.95),
  sidebarHover: rgb(0.90, 0.90, 0.90),
  sidebarActive: rgb(0.85, 0.85, 0.90),
  border: rgb(0.8, 0.8, 0.8),
};

export const nordTheme: Theme = {
  name: 'Nord',
  background: rgb(0.18, 0.22, 0.29), // #2E3440
  text: rgb(0.92, 0.93, 0.94), // #ECEFF4
  secondaryText: rgb(0.62, 0.67, 0.74), // #9DA7B8
  icon: rgb(0.82, 0.84, 0.87),
  syntax: rgb(0.44, 0.51, 0.60), // #4C566A
  codeBackground: rgb(0.23, 0.28, 0.35), // #3B4252
  blockquote: rgb(0.51, 0.63, 0.76), // #81A1C1
  link: rgb(0.53, 0.75, 0.82), // #88C0D0
  checkbox: rgb(0.64, 0.75, 0.55), // #A3BE8C
  checked: rgb(0.44, 0.51, 0.60),
  hr: rgb(0.44, 0.51, 0.60),
  wikiLink: rgb(0.56, 0.74, 0.73), // #8FBCBB
  wikiLinkMissing: rgb(0.75, 0.62, 0.53),
  tag: rgb(0.70, 0.56, 0.68),
  tagBackground: rgb(0.70, 0.56, 0.68, 0.18),
  cursor: rgb(0.85, 0.87, 0.91),
  sidebarBackground: rgb(0.15, 0.18, 0.24), // #262A34
  sidebarHover: rgb(0.21, 0.25, 0.32),
  sidebarActive: rgb(0.26, 0.31, 0.39),
  border: rgb(0.30, 0.35, 0.43),
};

export const solarizedTheme: Theme = {
  name: 'Solarized',
  background: rgb(0.0, 0.17, 0.21), // #002b36
  text: rgb(0.58, 0.63, 0.63), // #839496
  secondaryText: rgb(0.46, 0.53, 0.56),
  icon: rgb(0.66, 0.71, 0.71),
  syntax: rgb(0.40, 0.48, 0.51), // #586e75
  codeBackground: rgb(0.03, 0.21, 0.26), // #073642
  blockquote: rgb(0.42, 0.44, 0.77), // #6c71c4
  link: rgb(0.15, 0.55, 0.82), // #268bd2
  checkbox: rgb(0.52, 0.60, 0.0), // #859900
  checked: rgb(0.40, 0.48, 0.51),
  hr: rgb(0.40, 0.48, 0.51),
  wikiLink: rgb(0.16, 0.63, 0.60), // #2aa198
  wikiLinkMissing: rgb(0.80, 0.29, 0.09), // #cb4b16
  tag: rgb(0.83, 0.21, 0.51), // #d33682
  tagBackground: rgb(0.83, 0.21, 0.51, 0.18),
  cursor: rgb(0.58, 0.63, 0.63),
  sidebarBackground: rgb(0.0, 0.13, 0.16), // #001f24
  sidebarHover: rgb(0.02, 0.19, 0.23),
  sidebarActive: rgb(0.05, 0.23, 0.28),
  border: rgb(0.10, 0.30, 0.35),
};

export const sepiaTheme: Theme = {
  name: 'Sepia',
  background: rgb(0.96, 0.94, 0.88),
  text: rgb(0.35, 0.28, 0.20),
  secondaryText: rgb(0.55, 0.48, 0.40),
  icon: rgb(0.45, 0.38, 0.30),
  syntax: rgb(0.55, 0.48, 0.40, 0.5),
  codeBackground: rgb(0.40, 0.32, 0.22, 0.08),
  blockquote: rgb(0.55, 0.45, 0.35),
  link: rgb(0.40, 0.25, 0.10),
  checkbox: rgb(0.35, 0.50, 0.25),
  checked: rgb(0.60, 0.55, 0.50),
  hr: rgb(0.50, 0.42, 0.32, 0.4),
  wikiLink: rgb(0.30, 0.45, 0.50),
  wikiLinkMissing: rgb(0.65, 0.40, 0.25),
  tag: rgb(0.50, 0.40, 0.30),
  tagBackground: rgb(0.50, 0.40, 0.30, 0.12),
  cursor: rgb(0.35, 0.28, 0.20),
  sidebarBackground: rgb(0.93, 0.91, 0.85),
  sidebarHover: rgb(0.89, 0.87, 0.81),
  sidebarActive: rgb(0.85, 0.83, 0.77),
  border: rgb(0.75, 0.73, 0.67),
};

export const themes: { [key: string]: Theme } = {
  Dark: darkTheme,
  Light: lightTheme,
  Nord: nordTheme,
  Solarized: solarizedTheme,
  Sepia: sepiaTheme,
};

export const themeNames = Object.keys(themes);

export function getTheme(name: string): Theme {
  return themes[name] || darkTheme;
}
