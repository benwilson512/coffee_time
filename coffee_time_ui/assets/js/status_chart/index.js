import uPlot from "uplot";

const CHART_COLORS = {
  red: 'rgb(255, 99, 132)',
  orange: 'rgb(255, 159, 64)',
  yellow: 'rgb(255, 205, 86)',
  green: 'rgb(75, 192, 192)',
  blue: 'rgb(54, 162, 235)',
  purple: 'rgb(153, 102, 255)',
  grey: 'rgb(201, 203, 207)'
};

const data = {
  labels: [],
  datasets: [
    {
      label: 'Boiler Temp',
      data: [],
      borderColor: CHART_COLORS.red,
      cubicInterpolationMode: 'monotone',
      tension: 0.4
    },
    {
      label: 'CPU Temp',
      data: [],
      borderColor: CHART_COLORS.blue,
      cubicInterpolationMode: 'monotone',
      tension: 0.4
    }
  ]
};


const config = {
  type: 'line',
  data: data,
  options: {
    animation: false,
    responsive: true,
    plugins: {
      legend: {
        position: 'top',
      }
    }
  },
};

let chart;

function updateChart(chart, msg) {
  let {labels, points} = msg;
  console.log('points', points);
  let data = chart.data;

  data.labels = labels;
  data.datasets.forEach(dataset => {
    dataset.data = points[dataset.label];
  });

  console.log('data', data);

  chart.update();
}

export const StatusChart = {
  mounted() {

  chart = new Chart(
    this.el,
    config
  );

  this.handleEvent("points", (msg) => updateChart(chart, msg))

  }
};