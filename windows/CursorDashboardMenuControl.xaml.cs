using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.TextFormatting;
using AIUsage.Windows.Models;
using AIUsage.Windows.Services;

namespace AIUsage.Windows;

public partial class CursorDashboardMenuControl : UserControl
{
    /// <summary>Mac CursorDashboardTheme.panelWidth（表の列幅合計 + horizontalInset×2）</summary>
    public const double HorizontalInset = 12;
    public const double PanelContentWidth = 210 + 88 + 88 + 72;
    public const double PanelOuterWidth = PanelContentWidth + HorizontalInset * 2;

    private const double GridGap = 8;
    private const double CardCorner = 8;
    private const double PanelWidth = PanelContentWidth;

    private static readonly Color[] ChartColors =
    [
        Color.FromRgb(158, 196, 254), Color.FromRgb(182, 227, 193), Color.FromRgb(247, 197, 160),
        Color.FromRgb(211, 185, 242), Color.FromRgb(245, 184, 197), Color.FromRgb(167, 224, 224),
        Color.FromRgb(240, 217, 155), Color.FromRgb(201, 212, 240),
    ];

    private TextBlock? _resetHeader;
    /// <summary>ContextMenu 内では <see cref="ToggleButton"/> がテンプレ階層で落ちることがあるため通常 <see cref="Button"/> を使用</summary>
    private readonly List<Button> _durationButtons = [];
    private CursorDashboardBundle? _bundle;
    private UsageDuration _duration = UsageDuration.BillingCycle;
    private double? _exchangeRate;
    private CursorStackedBarChart? _chart;
    private WrapPanel? _legendPanel;
    private ListView? _tableList;

    private sealed class ModelTableRow
    {
        public string Model { get; init; } = "";
        public string Requests { get; init; } = "";
        public string Tokens { get; init; } = "";
        public string Spend { get; init; } = "";
    }

    public CursorDashboardMenuControl()
    {
        InitializeComponent();
        Loaded += (_, _) => ApplyTheme();
    }

    public void Update(CursorDashboardBundle? bundle, double? exchangeRate)
    {
        _bundle = bundle;
        _exchangeRate = exchangeRate;
        BuildLayout();
    }

    private void ApplyTheme()
    {
        Background = WindowsTheme.MenuBackgroundBrush() ?? Brushes.White;
        Foreground = WindowsTheme.MenuForegroundBrush();
    }

    private void BuildLayout()
    {
        if (RootGrid is null) return;
        RootGrid.Children.Clear();
        RootGrid.ColumnDefinitions.Clear();
        RootGrid.RowDefinitions.Clear();
        _durationButtons.Clear();

        var main = new StackPanel { Orientation = Orientation.Vertical, Width = PanelWidth };

        _resetHeader = new TextBlock
        {
            FontSize = 12,
            Margin = new Thickness(0, 0, 0, 4),
            Foreground = MutedBrush(),
            Visibility = Visibility.Collapsed,
        };
        main.Children.Add(_resetHeader);

        var cardsRow = new Grid { Margin = new Thickness(0, 0, 0, 14) };
        cardsRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.7, GridUnitType.Star) });
        cardsRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        cardsRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.3, GridUnitType.Star) });

        var leftCol = new StackPanel { Orientation = Orientation.Vertical, MinWidth = 0 };
        var rightCol = new StackPanel { Orientation = Orientation.Vertical, MinWidth = 0 };
        Grid.SetColumn(leftCol, 0);
        Grid.SetColumn(rightCol, 2);
        cardsRow.Children.Add(leftCol);
        cardsRow.Children.Add(rightCol);

        var bundle = _bundle;
        var snap = bundle?.Snapshot;
        if (snap?.ErrorMessage is { } err && err is "not_logged_in" or "not_installed" or "setup_failed")
        {
            var msg = err == "not_logged_in" ? Localizer.Get("notLoggedIn") : Localizer.Get("unavailable");
            AddSummaryCardToColumn(leftCol, MakeSummaryCard(Localizer.Get("unavailable"), msg, null, false));
        }
        else if (snap is not null)
        {
            AddSummaryCardToColumn(leftCol, MakeSummaryCard(Localizer.Get("dash.card.total"),
                CursorDashboardFormatter.FormatDashPercent(snap.TotalPercentUsed), snap.TotalPercentUsed, true));
            AddSummaryCardToColumn(rightCol, MakeSummaryCard(Localizer.Get("dash.card.auto"),
                CursorDashboardFormatter.FormatDashPercent(snap.AutoPercentUsed), snap.AutoPercentUsed, true));

            if (snap.OnDemand == CursorOnDemandState.Disabled)
                AddSummaryCardToColumn(leftCol, MakeSummaryCard(Localizer.Get("dash.card.ondemand"), "—", null, false));
            else if (snap.OnDemand == CursorOnDemandState.Limited && snap.OnDemandLimitDollars is > 0)
            {
                var spend = snap.OnDemandSpendDollars;
                var limit = snap.OnDemandLimitDollars;
                var primary = CurrencyService.FormatOnDemand(spend, _exchangeRate, Settings.Currency);
                var ratio = Math.Min(100, spend / limit.Value * 100);
                var usd = CursorDashboardFormatter.FormatUsdSecondary((int)Math.Round(spend * 100));
                AddSummaryCardToColumn(leftCol, MakeSummaryCardOnDemand(primary, usd, ratio));
            }
            else
                AddSummaryCardToColumn(leftCol, MakeSummaryCard(Localizer.Get("dash.card.ondemand"),
                    CurrencyService.FormatOnDemand(snap.OnDemandSpendDollars, _exchangeRate, Settings.Currency), null, false));

            AddSummaryCardToColumn(rightCol, MakeSummaryCard(Localizer.Get("dash.card.api"),
                CursorDashboardFormatter.FormatDashPercent(snap.ApiPercentUsed), snap.ApiPercentUsed, true));
        }

        if (snap?.ResetsAt is { } resetAt)
        {
            _resetHeader!.Visibility = Visibility.Visible;
            _resetHeader.Text = string.Format(CultureInfo.CurrentCulture, Localizer.Get("dash.reset_header"),
                resetAt.ToLocalTime().ToString("yyyy/MM/dd HH:mm", CultureInfo.CurrentCulture));
        }

        main.Children.Add(cardsRow);

        var durRow = new UniformGrid { Rows = 1, Columns = 4, Margin = new Thickness(0, 0, 0, 8) };
        var durs = (UsageDuration[])[UsageDuration.Hours24, UsageDuration.Days7, UsageDuration.Days30, UsageDuration.BillingCycle];
        for (var i = 0; i < durs.Length; i++)
        {
            var d = durs[i];
            var btn = new Button
            {
                Content = Localizer.Get(DurationKey(d)),
                Tag = d,
                Padding = new Thickness(6, 4, 6, 4),
                FontSize = 11,
                Focusable = false,
                Cursor = System.Windows.Input.Cursors.Hand,
            };
            btn.Click += DurationButtonClick;
            _durationButtons.Add(btn);
            durRow.Children.Add(btn);
        }
        main.Children.Add(durRow);

        _chart = new CursorStackedBarChart { Height = 152, Margin = new Thickness(0, 0, 0, 4) };
        main.Children.Add(_chart);

        _legendPanel = new WrapPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        main.Children.Add(_legendPanel);

        var gridView = new GridView();
        gridView.Columns.Add(new GridViewColumn
        {
            Header = Localizer.Get("dash.col.model"),
            Width = 210,
            CellTemplate = TableCellTemplate(nameof(ModelTableRow.Model), isNumeric: false),
        });
        gridView.Columns.Add(new GridViewColumn
        {
            Header = Localizer.Get("dash.col.requests"),
            Width = 88,
            CellTemplate = TableCellTemplate(nameof(ModelTableRow.Requests), isNumeric: true),
        });
        gridView.Columns.Add(new GridViewColumn
        {
            Header = Localizer.Get("dash.col.tokens"),
            Width = 88,
            CellTemplate = TableCellTemplate(nameof(ModelTableRow.Tokens), isNumeric: true),
        });
        gridView.Columns.Add(new GridViewColumn
        {
            Header = Localizer.Get("dash.col.spend"),
            Width = 72,
            CellTemplate = TableCellTemplate(nameof(ModelTableRow.Spend), isNumeric: true),
        });

        _tableList = new ListView
        {
            View = gridView,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Margin = new Thickness(0, 4, 0, 0),
            MaxHeight = 240,
            FontSize = 11,
            Foreground = WindowsTheme.MenuForegroundBrush(),
        };
        ScrollViewer.SetCanContentScroll(_tableList, true);
        ScrollViewer.SetVerticalScrollBarVisibility(_tableList, ScrollBarVisibility.Auto);
        ScrollViewer.SetHorizontalScrollBarVisibility(_tableList, ScrollBarVisibility.Disabled);
        main.Children.Add(_tableList);

        RootGrid.Children.Add(main);
        UpdateDurationSelection();
        ReloadDurationViews();
    }

    private static string DurationKey(UsageDuration d) => d switch
    {
        UsageDuration.Hours24 => "dash.duration.24h",
        UsageDuration.Days7 => "dash.duration.7d",
        UsageDuration.Days30 => "dash.duration.30d",
        _ => "dash.duration.cycle",
    };

    private void DurationButtonClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button tb && tb.Tag is UsageDuration dur)
        {
            _duration = dur;
            UpdateDurationSelection();
            ReloadDurationViews();
        }
    }

    private void UpdateDurationSelection()
    {
        foreach (var btn in _durationButtons)
        {
            var selected = Equals(btn.Tag, _duration);
            StyleDurationButton(btn, selected);
        }
    }

    private void StyleDurationButton(Button btn, bool selected)
    {
        var accent = WindowsTheme.ControlAccentBrush();

        if (selected)
        {
            btn.Background = accent;
            btn.Foreground = Brushes.White;
        }
        else
        {
            btn.Background = new SolidColorBrush(Color.FromArgb(20, 128, 128, 128));
            btn.Foreground = MutedBrush();
        }
    }

    private void ReloadDurationViews()
    {
        var bundle = _bundle;
        if (bundle is null || _chart is null || _legendPanel is null || _tableList is null) return;
        var now = DateTimeOffset.UtcNow;
        var stacked = CursorModelBreakdown.DailyStackedTokenSeries(
            bundle.Events, _duration, bundle.Snapshot.ResetsAt, now);
        _chart.SetData(stacked, ChartColors, MutedBrush());

        _legendPanel.Children.Clear();
        foreach (var (model, _) in stacked.Series.Take(ChartColors.Length))
        {
            var i = _legendPanel.Children.Count;
            var color = ChartColors[i % ChartColors.Length];
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 10, 2) };
            row.Children.Add(new Border
            {
                Width = 10,
                Height = 10,
                CornerRadius = new CornerRadius(2),
                Background = new SolidColorBrush(color),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 4, 0),
            });
            row.Children.Add(new TextBlock { Text = model, FontSize = 9, Foreground = MutedBrush(), VerticalAlignment = VerticalAlignment.Center });
            _legendPanel.Children.Add(row);
        }

        var aggRows = CursorModelBreakdown.AggregateByModel(
            bundle.Events, bundle.DailySpend, _duration, bundle.Snapshot.ResetsAt, now);

        if (aggRows.Count == 0)
        {
            _tableList.ItemsSource = new List<ModelTableRow>
            {
                new ModelTableRow
                {
                    Model = Localizer.Get("dash.table.empty"),
                    Requests = "",
                    Tokens = "",
                    Spend = "",
                },
            };
            return;
        }

        _tableList.ItemsSource = aggRows.Select(row => new ModelTableRow
        {
            Model = row.Model,
            Requests = $"{row.Requests:0.0}",
            Tokens = CursorDashboardFormatter.FormatDashTokens(row.Tokens),
            Spend = CursorDashboardFormatter.FormatSpendCents(row.SpendCents, _exchangeRate, Settings.Currency),
        }).ToList();
    }

    private static Brush MutedBrush() =>
        new SolidColorBrush(Color.FromRgb(128, 128, 128));

    /// <summary>左右は Grid の中央列 8px がガター。上下は StackPanel なので 2 枚目以降に上マージンで <see cref="GridGap"/> を合わせる。</summary>
    private void AddSummaryCardToColumn(Panel column, Border card)
    {
        if (column.Children.Count > 0)
            card.Margin = new Thickness(0, GridGap, 0, 0);
        column.Children.Add(card);
    }

    private Border MakeSummaryCard(string title, string value, double? ratio, bool showBar)
    {
        var border = CardShell();
        var stack = new StackPanel { Margin = new Thickness(14, 8, 14, 8) };
        stack.Children.Add(new TextBlock { Text = title, FontSize = 11, FontWeight = FontWeights.Medium, Foreground = MutedBrush() });
        stack.Children.Add(new TextBlock
        {
            Text = value,
            FontSize = 22,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 4, 0, 0),
            Foreground = WindowsTheme.MenuForegroundBrush(),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        if (showBar)
            stack.Children.Add(new ProgressBarMini(ratio ?? 0));
        else
            stack.Children.Add(new ProgressBarMini(0));
        border.Child = stack;
        border.MinHeight = 76;
        return border;
    }

    private Border MakeSummaryCardOnDemand(string primary, string usdSecondary, double ratioPercent)
    {
        var border = CardShell();
        var stack = new StackPanel { Margin = new Thickness(14, 8, 14, 8) };
        stack.Children.Add(new TextBlock { Text = Localizer.Get("dash.card.ondemand"), FontSize = 11, FontWeight = FontWeights.Medium, Foreground = MutedBrush() });
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        row.Children.Add(new TextBlock
        {
            Text = primary,
            FontSize = 22,
            FontWeight = FontWeights.SemiBold,
            Foreground = WindowsTheme.MenuForegroundBrush(),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        row.Children.Add(new TextBlock
        {
            Text = " " + usdSecondary,
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(4, 0, 0, 2),
            Foreground = new SolidColorBrush(Color.FromRgb(120, 120, 120)),
        });
        stack.Children.Add(row);
        stack.Children.Add(new ProgressBarMini(ratioPercent));
        border.Child = stack;
        border.MinHeight = 76;
        return border;
    }

    private Border CardShell() => new()
    {
        Background = WindowsTheme.MenuBackgroundBrush() ?? WindowsTheme.PanelBackgroundBrush(),
        CornerRadius = new CornerRadius(CardCorner),
        BorderBrush = WindowsTheme.PanelHairlineBorderBrush(),
        BorderThickness = new Thickness(1),
        SnapsToDevicePixels = true,
    };

    /// <summary>GridView のセルを右寄せ（数値）・省略（モデル名）で Mac 寄せにする。</summary>
    private static DataTemplate TableCellTemplate(string propertyName, bool isNumeric)
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(FrameworkElement.MarginProperty, new Thickness(0));
        border.SetValue(Border.PaddingProperty, new Thickness(8, 4, 8, 4));

        var tb = new FrameworkElementFactory(typeof(TextBlock));
        tb.SetBinding(TextBlock.TextProperty, new Binding(propertyName));
        tb.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center);
        tb.SetValue(TextBlock.FontSizeProperty, 11.0);
        tb.SetValue(TextBlock.ForegroundProperty, WindowsTheme.MenuForegroundBrush());
        tb.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Stretch);
        if (isNumeric)
            tb.SetValue(TextBlock.TextAlignmentProperty, TextAlignment.Right);
        else
        {
            tb.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis);
            tb.SetValue(TextBlock.TextWrappingProperty, TextWrapping.NoWrap);
        }

        border.AppendChild(tb);
        return new DataTemplate { VisualTree = border };
    }

    private sealed class ProgressBarMini : FrameworkElement
    {
        private readonly double _ratio;

        public ProgressBarMini(double ratioPercent)
        {
            _ratio = Math.Clamp(ratioPercent / 100.0, 0, 1);
            Height = 6;
        }

        protected override void OnRender(DrawingContext dc)
        {
            var w = ActualWidth > 0 ? ActualWidth : 100;
            dc.DrawRoundedRectangle(
                new SolidColorBrush(Color.FromArgb(20, 0, 0, 0)), null,
                new Rect(0, 0, w, Height), 2, 2);
            if (_ratio > 0)
            {
                var fill = WindowsTheme.ControlAccentBrush();
                dc.DrawRoundedRectangle(fill, null, new Rect(0, 0, w * _ratio, Height), 2, 2);
            }
        }

        protected override Size MeasureOverride(Size availableSize)
        {
            var w = double.IsPositiveInfinity(availableSize.Width) ? 100 : Math.Max(0, availableSize.Width);
            return new Size(w, Height);
        }
    }

    private sealed class CursorStackedBarChart : FrameworkElement
    {
        private (IReadOnlyList<DateTime> Days, IReadOnlyList<(string Model, IReadOnlyDictionary<DateTime, int> TokensByDay)> Series)? _data;
        private Color[] _palette = [];
        private Brush _muted = Brushes.Gray;

        public CursorStackedBarChart()
        {
            SnapsToDevicePixels = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        }

        public void SetData(
            (IReadOnlyList<DateTime> Days, IReadOnlyList<(string Model, IReadOnlyDictionary<DateTime, int> TokensByDay)> Series) data,
            Color[] palette,
            Brush muted)
        {
            _data = data;
            _palette = palette;
            _muted = muted;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext dc)
        {
            var width = ActualWidth > 0 ? ActualWidth : PanelWidth;
            var height = ActualHeight > 0 ? ActualHeight : 152;
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, width, height));

            if (_data is not { Days: { Count: > 0 } days, Series: var series })
            {
                var ft = new FormattedText(
                    Localizer.Get("dash.chart.empty"),
                    CultureInfo.CurrentCulture,
                    FlowDirection.LeftToRight,
                    new Typeface("Segoe UI"),
                    11,
                    _muted,
                    new NumberSubstitution(),
                    TextFormattingMode.Display,
                    VisualTreeHelper.GetDpi(this).PixelsPerDip);
                dc.DrawText(ft, new Point(8, 24));
                return;
            }

            const double yAxisW = 42;
            const double xAxisH = 18;
            var plot = new Rect(yAxisW + 4, 4, width - yAxisW - 8, height - xAxisH - 8);

            var dataMax = 1;
            foreach (var day in days)
            {
                var total = series.Sum(s => s.TokensByDay.GetValueOrDefault(day));
                dataMax = Math.Max(dataMax, total);
            }
            var axisMax = NiceAxisMaximum(dataMax);
            var ticks = YAxisTickValues(axisMax);

            foreach (var tick in ticks)
            {
                var ratio = axisMax > 0 ? tick / (double)axisMax : 0;
                var y = plot.Bottom - ratio * plot.Height;
                dc.DrawLine(new Pen(new SolidColorBrush(Color.FromArgb(30, 128, 128, 128)), 0.5),
                    new Point(plot.Left, y), new Point(plot.Right, y));
                var label = CursorDashboardFormatter.FormatChartAxisTokens(tick);
                var ft = new FormattedText(label, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                    new Typeface("Segoe UI"), 9, _muted, new NumberSubstitution(), TextFormattingMode.Display, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                dc.DrawText(ft, new Point(plot.Left - yAxisW + 4, y - ft.Height / 2));
            }

            var count = days.Count;
            var barW = Math.Max(1, plot.Width / count - 2);
            for (var idx = 0; idx < count; idx++)
            {
                var day = days[idx];
                var x = plot.Left + idx * (plot.Width / count) + 1;
                var y = plot.Bottom;
                for (var sIdx = 0; sIdx < series.Count; sIdx++)
                {
                    var tokens = series[sIdx].TokensByDay.GetValueOrDefault(day);
                    if (tokens <= 0) continue;
                    var h = plot.Height * (tokens / (double)axisMax);
                    var c = _palette[sIdx % _palette.Length];
                    dc.DrawRectangle(new SolidColorBrush(c), null, new Rect(x, y - h, barW, h));
                    y -= h;
                }
            }

            var labelIndices = XLabelDayIndices(count);
            foreach (var li in labelIndices)
            {
                var day = days[li];
                var text = day.ToString("M/d", CultureInfo.CurrentCulture);
                var ft = new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                    new Typeface("Segoe UI"), 9, _muted, new NumberSubstitution(), TextFormattingMode.Display, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                var centerX = plot.Left + (li + 0.5) * (plot.Width / count);
                dc.DrawText(ft, new Point(centerX - ft.Width / 2, plot.Bottom + 2));
            }
        }

        private static int NiceAxisMaximum(int dataMax)
        {
            if (dataMax <= 0) return 1;
            const int intervalCount = 5;
            var rawStep = dataMax / (double)intervalCount;
            var magnitude = Math.Pow(10, Math.Floor(Math.Log10(Math.Max(rawStep, 1))));
            var normalized = rawStep / magnitude;
            double niceNormalized = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
            var step = Math.Max(1, (int)(niceNormalized * magnitude));
            var niceMax = step * intervalCount;
            if (niceMax < dataMax) niceMax = step * (intervalCount + 1);
            return niceMax;
        }

        private static int[] YAxisTickValues(int maximum)
        {
            if (maximum <= 0) return [0];
            const int intervalCount = 5;
            var step = Math.Max(1, maximum / intervalCount);
            return Enumerable.Range(0, intervalCount + 1).Select(i => i * step).ToArray();
        }

        private static int[] XLabelDayIndices(int dayCount)
        {
            if (dayCount <= 0) return [];
            if (dayCount == 1) return [0];
            const int maxLabels = 8;
            if (dayCount <= maxLabels) return Enumerable.Range(0, dayCount).ToArray();
            var indices = new List<int> { 0 };
            var idx = 0;
            var minGap = Math.Max(3, dayCount / (maxLabels - 1));
            while (idx + minGap < dayCount - 1)
            {
                idx += minGap;
                indices.Add(idx);
            }
            if (indices[^1] != dayCount - 1) indices.Add(dayCount - 1);
            return indices.ToArray();
        }
    }
}
