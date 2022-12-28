import uPlot from "uplot";


export const StatusChart = {
  mounted() {

    console.time("chart");

    const opts = {
      title: "Server Events",
      width: 1920,
      height: 600,
    //	ms:     1,
    //	cursor: {
    //		x: false,
    //		y: false,
    //	},
      series: [
        {},
        {
          label: "CPU",
          scale: "%",
          value: (u, v) => v == null ? "-" : v.toFixed(1) + "%",
          stroke: "red",
          width: 1/devicePixelRatio,
        },
        {
          label: "RAM",
          scale: "%",
          value: (u, v) => v == null ? "-" : v.toFixed(1) + "%",
          stroke: "blue",
          width: 1/devicePixelRatio,
        },
        {
          label: "TCP Out",
          scale: "mb",
          value: (u, v) => v == null ? "-" : v.toFixed(2) + " MB",
          stroke: "green",
          width: 1/devicePixelRatio,
        }
      ],
      axes: [
        {},
        {
          scale: "%",
          values: (u, vals, space) => vals.map(v => +v.toFixed(1) + "%"),
        },
        {
          side: 1,
          scale: "mb",
          size: 60,
          values: (u, vals, space) => vals.map(v => +v.toFixed(2) + " MB"),
          grid: {show: false},
        },
      ],
    };

    let data = prepData(packed);
    let uplot = new uPlot(opts, data, this.el);
  }
};