import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Sports Hub: scripts/cricket reads Cricbuzz, scripts/sports reads ESPN's
// public scoreboards and Jolpica (F1). Both write a cache under
// ~/.cache/omarchy/sports-hub/ that every bar shares, and send the
// notifications. The bar shows the live score of a followed team.
Panel {
  id: root
  moduleName: "io.github.rajshimpi.sports-hub"
  ipcTarget: "io.github.rajshimpi.sports-hub"
  manageIpc: true

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/omarchy/sports-hub"
  readonly property string cricketHelper: Qt.resolvedUrl("scripts/cricket").toString().replace(/^file:\/\//, "")
  readonly property string sportsHelper: Qt.resolvedUrl("scripts/sports").toString().replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var allTabs: ["live", "cricket", "football", "f1", "tennis", "basketball", "nfl", "hockey", "baseball", "golf", "mma"]
  readonly property var tabNames: ({ live: "Live", cricket: "Cricket", football: "Football", f1: "F1", tennis: "Tennis",
                                     basketball: "Basketball", nfl: "NFL", hockey: "Hockey", baseball: "Baseball", golf: "Golf", mma: "MMA" })
  // Nerd Font (Material Design) glyphs: md-scoreboard, md-cricket, md-soccer, md-flag_checkered, md-tennis_ball,
  // md-basketball, md-football, md-hockey_puck, md-baseball, md-golf, md-boxing_glove.
  readonly property var glyphs: ({ hub: 0xf127e, cricket: 0xf0d6d, football: 0xf04b8, f1: 0xf023c, tennis: 0xf0507, basketball: 0xf0806,
                                   nfl: 0xf025d, hockey: 0xf0879, baseball: 0xf0852, golf: 0xf0823, mma: 0xf0b65 })
  function glyph(sport) { return String.fromCodePoint(glyphs[sport] || glyphs.hub) }

  property var cric: ({ matches: [], follow: [] })
  property var sport: ({ events: {}, f1: {} })
  property string tab: "live"
  property bool showAll: false
  property string error: ""

  readonly property var tabs: (sport.tabs && sport.tabs.length) ? sport.tabs : allTabs
  readonly property string current: tabs.indexOf(tab) >= 0 ? tab : tabs[0]
  readonly property bool cricketOn: tabs.indexOf("cricket") >= 0
  readonly property var events: sport.events || ({})
  readonly property var f1: sport.f1 || ({})

  // ---------- cricket ----------
  readonly property var head: cricketOn ? (cric.headline || null) : null
  readonly property bool anyLive: (cric.matches || []).some(function(m) { return m.live })
  readonly property var shownCricket: (cric.matches || []).filter(cricketVisible).slice(0, 25)

  function isFollowed(m) {
    var f = (cric.follow || []).map(function(x) { return x.toLowerCase() })
    return f.indexOf(m.team1.name.toLowerCase()) >= 0 || f.indexOf(m.team2.name.toLowerCase()) >= 0
        || f.indexOf(m.team1.short.toLowerCase()) >= 0 || f.indexOf(m.team2.short.toLowerCase()) >= 0
  }
  // Followed teams and internationals; "All matches" adds domestic, league and women's cricket.
  function cricketVisible(m) { return root.showAll || isFollowed(m) || m.type === "International" }

  // ---------- everything else ----------
  readonly property var liveEvents: {
    var out = []
    for (var i = 0; i < tabs.length; i++)
      (events[tabs[i]] || []).forEach(function(e) { if (e.state === "in") out.push(e) })
    return mineFirst(out, function(e) { return e.follow })
  }
  // Followed first, otherwise keep the order (Array.sort is not stable in every engine).
  function mineFirst(list, isMine) {
    return list.map(function(x, i) { return { x: x, i: i, m: isMine(x) ? 0 : 1 } })
               .sort(function(a, b) { return a.m - b.m || a.i - b.i })
               .map(function(o) { return o.x })
  }
  readonly property bool f1Racing: !!(f1.next && f1.next.start <= Date.now() / 1000 && Date.now() / 1000 < f1.next.start + 7200)

  // The bar: a followed live cricket match, else a followed live game, else any live football.
  readonly property var barEvent: {
    var matches = liveEvents.filter(function(e) { return e.kind === "match" })
    return matches.filter(function(e) { return e.follow })[0] || matches.filter(function(e) { return e.sport === "football" })[0] || null
  }
  readonly property string barText: {
    if (head) {
      // Show the side that is batting now: the one with the most recent innings.
      var bat = head.team2.score !== "" ? head.team2 : head.team1
      return bat.short + " " + bat.score.split(" & ").pop().replace(/ \(.*\)/, "")
    }
    if (!barEvent) return ""
    var a = barEvent.rows[0], b = barEvent.rows[1]
    // Tennis: just the set being played.
    var sa = barEvent.sport === "tennis" ? a.score.split(" ").pop() : a.score
    var sb = barEvent.sport === "tennis" ? b.score.split(" ").pop() : b.score
    return (a.short || a.name) + " " + sa + "–" + sb + " " + (b.short || b.name)
  }
  readonly property string barGlyph: glyph(head ? "cricket" : barEvent ? barEvent.sport : "hub")

  readonly property string followingText: {
    var f = (cricketOn ? (cric.follow || []) : []).concat(sport.followTeams || [])
    return f.length ? "following " + f.join(", ") : "live scores"
  }

  function tabLive(t) {
    if (t === "live") return liveCards.length > 0
    if (t === "cricket") return (cric.matches || []).some(function(m) { return m.state === "In Progress" && cricketVisible(m) })
    if (t === "f1") return f1Racing
    return (events[t] || []).some(function(e) { return e.state === "in" })
  }

  // ---------- cards ----------
  // Every list shows the same card: badge + header, optional title, name/score rows, footer.
  function cricketCard(m, tagged) {
    var upcoming = m.state === "Preview" || m.state === "Upcoming"
    return {
      badge: m.live ? (m.state === "In Progress" ? "LIVE" : m.state.toUpperCase()) : "",
      hot: m.state === "In Progress",
      header: (tagged ? glyph("cricket") + "  " : "") + m.desc + " · " + m.format + " · " + m.series,
      title: "",
      rows: [{ name: m.team1.name, score: m.team1.score || "—", win: false }, { name: m.team2.name, score: m.team2.score || "—", win: false }],
      foot: upcoming ? "Starts " + when(m.start) : m.status,
      accent: m.live,
      url: m.url,
      mine: isFollowed(m)
    }
  }
  function eventCard(e, tagged) {
    return {
      badge: e.state === "in" ? "LIVE" : "",
      hot: e.state === "in",
      header: (tagged ? glyph(e.sport) + "  " : "") + e.league,
      title: e.title || "",
      rows: e.rows.map(function(r) { return { name: r.name, score: e.kind === "match" && e.state === "pre" ? "" : r.score, win: r.win } }),
      foot: e.state === "pre" && e.start > Date.now() / 1000 ? when(e.start) + "  ·  in " + countdown(e.start) : e.detail,
      accent: e.state === "in",
      url: e.url,
      mine: !!e.follow
    }
  }
  function f1Card() {
    var n = f1.next
    return {
      badge: "LIVE", hot: true, header: glyph("f1") + "  Formula 1 · Round " + n.round, title: n.name, rows: [],
      foot: n.circuit + ", " + n.country, accent: true, url: n.url, mine: false
    }
  }

  readonly property var liveCards: {
    var out = []
    if (cricketOn)
      (cric.matches || []).forEach(function(m) { if (m.live && cricketVisible(m)) out.push(cricketCard(m, true)) })
    liveEvents.forEach(function(e) { out.push(eventCard(e, true)) })
    if (f1Racing && tabs.indexOf("f1") >= 0) out.push(f1Card())
    return mineFirst(out, function(c) { return c.mine })
  }
  readonly property var upcomingCards: {
    var now = Date.now() / 1000, soon = []
    if (cricketOn)
      (cric.matches || []).forEach(function(m) {
        if ((m.state === "Preview" || m.state === "Upcoming") && cricketVisible(m)) soon.push({ start: m.start, mine: isFollowed(m), card: cricketCard(m, true) })
      })
    for (var i = 0; i < tabs.length; i++)
      (events[tabs[i]] || []).forEach(function(e) {
        if (e.state === "pre" && e.start > now) soon.push({ start: e.start, mine: e.follow, card: eventCard(e, true) })
      })
    soon.sort(function(a, b) { return (b.mine ? 1 : 0) - (a.mine ? 1 : 0) || a.start - b.start })
    return soon.slice(0, 6).map(function(x) { return x.card })
  }
  readonly property var sections: {
    if (current === "live")
      return [{ title: "LIVE NOW", cards: liveCards, empty: "Nothing live right now" },
              { title: "COMING UP", cards: upcomingCards, empty: "" }]
    if (current === "cricket")
      return [{ title: "", cards: shownCricket.map(function(m) { return cricketCard(m, false) }),
                empty: root.showAll ? "No matches right now" : "No international or followed matches right now" }]
    if (current === "f1") return []
    return [{ title: "", cards: (events[current] || []).map(function(e) { return eventCard(e, false) }),
              empty: "Nothing on in the next day or so" }]
  }

  function kickoff(ts) { return Qt.formatDateTime(new Date(ts * 1000), "ddd d MMM · HH:mm") }
  function when(ts) { return Qt.formatDateTime(new Date(ts * 1000), "ddd d MMM, HH:mm") }
  function countdown(ts) {
    var s = ts - Date.now() / 1000
    if (s <= 0) return "now"
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), mnt = Math.floor(s % 3600 / 60)
    return (d ? d + "d " : "") + (h ? h + "h " : "") + (d ? "" : mnt + "m")
  }

  // Cricket: a followed match live every 30 s, anything else live every 2 min, else 15 min.
  // Other sports: a followed game live every minute, anything live every 3 min, else 10 min.
  // Every bar shares the caches, so only refresh when they are older than that.
  readonly property int cricketEvery: head ? 30 : anyLive ? 120 : 900
  readonly property int sportsEvery: liveEvents.some(function(e) { return e.follow }) ? 60 : liveEvents.length ? 180 : 600
  function refresh(force) {
    var now = Date.now() / 1000
    if (cricketOn && !cricketProc.running && (force || now - (cric.at || 0) >= cricketEvery - 2)) cricketProc.running = true
    if (!sportsProc.running && (force || now - (sport.at || 0) >= sportsEvery - 2)) sportsProc.running = true
  }

  function moveTab(step) {
    var i = tabs.indexOf(current)
    tab = tabs[(i + step + tabs.length) % tabs.length]
    list.contentY = 0
  }

  onOpenedChanged: if (opened) refresh(true)

  FileView {
    id: cricketFile
    path: root.cacheDir + "/cricket.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.cric = JSON.parse(text()) } catch (e) {} }
  }

  FileView {
    id: sportsFile
    path: root.cacheDir + "/sports.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.sport = JSON.parse(text()) } catch (e) {} }
  }

  // The helpers also print what they wrote: that covers the first run, when
  // the cache files did not exist yet for the FileViews to watch.
  Process {
    id: cricketProc
    command: [root.cricketHelper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.error = d.error || ""
          if (d.matches) root.cric = d
        } catch (e) { root.error = "No cricket data" }
        cricketFile.reload()
      }
    }
  }

  Process {
    id: sportsProc
    command: [root.sportsHelper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { var d = JSON.parse(text); if (d.events) root.sport = d } catch (e) {}
        sportsFile.reload()
      }
    }
  }

  Timer { interval: 10000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh(false) }

  implicitWidth: barRow.implicitWidth
  implicitHeight: button.implicitHeight

  Row {
    id: barRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      text: root.barGlyph
      tooltipText: root.head ? root.head.team1.short + " " + (root.head.team1.score || "-") + " v " + root.head.team2.short + " " + (root.head.team2.score || "-") + " — " + root.head.status
                 : root.barEvent ? root.barEvent.league + " · " + root.barEvent.detail : "Sports"
      onPressed: function(b) { root.toggle() }
    }

    Text {
      visible: root.barText !== ""
      anchors.verticalCenter: parent.verticalCenter
      rightPadding: Style.space(6)
      text: root.barText
      color: root.fg
      font.family: root.font
      font.pixelSize: Style.font.caption
      font.bold: true
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggle() }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: barRow
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx) root.moveTab(dx)
        else list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + dy * Style.space(60)))
      }
      onTextKey: function(t) { if (t === "r") root.refresh(true) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Item {
          width: parent.width
          implicitHeight: hero.implicitHeight
          Row {
            id: hero
            spacing: Style.space(14)
            Text { text: root.glyph("hub"); color: root.fg; font.family: root.font; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text { text: "Sports"; color: root.fg; font.family: root.font; font.pixelSize: Style.font.title; font.bold: true }
              Text {
                text: (root.followingText + (cricketProc.running || sportsProc.running ? " · updating…" : "")).toUpperCase()
                color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2
              }
            }
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Button {
              visible: root.current === "cricket" || root.current === "live"
              text: root.showAll ? "Top matches" : "All matches"
              tooltipText: root.showAll ? "Only followed teams and internationals" : "Add domestic, league and women's cricket"
              fontSize: Style.font.caption
              foreground: root.fg; fontFamily: root.font; bordered: true
              onClicked: root.showAll = !root.showAll
            }
            Button {
              iconText: "󰏫"; tooltipText: "Sports, leagues, teams to follow, notifications"
              foreground: root.fg; fontFamily: root.font
              onClicked: { Quickshell.execDetached([root.sportsHelper, "edit"]); root.close() }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.tabs
            delegate: Button {
              required property string modelData
              text: (root.tabNames[modelData] || modelData) + (root.tabLive(modelData) ? " ●" : "")
              selected: root.current === modelData
              bordered: true
              fontSize: Style.font.caption
              foreground: root.fg; fontFamily: root.font
              onClicked: { root.tab = modelData; list.contentY = 0 }
            }
          }
        }

        Text {
          visible: root.error !== "" && root.current === "cricket"
          text: root.error
          color: "#e5484d"; font.family: root.font; font.pixelSize: Style.font.bodySmall
        }

        // ---------- Formula 1 ----------
        Column {
          id: f1col
          visible: root.current === "f1"
          width: parent.width
          spacing: Style.space(10)
          Rectangle {
            visible: !!root.f1.next
            width: parent.width
            implicitHeight: nextCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
            Column {
              id: nextCol
              anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(3)
              readonly property var n: root.f1.next || ({})
              Text { text: "NEXT RACE · ROUND " + (nextCol.n.round || ""); color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.1 }
              Text { text: root.glyph("f1") + "  " + (nextCol.n.name || ""); color: root.fg; font.family: root.font; font.pixelSize: Style.font.body; font.bold: true }
              Text { text: (nextCol.n.circuit || "") + ", " + (nextCol.n.country || ""); color: Qt.darker(root.fg, 1.3); font.family: root.font; font.pixelSize: Style.font.caption }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Race " + root.kickoff(nextCol.n.start || 0) + "  (in " + root.countdown(nextCol.n.start || 0) + ")" + (nextCol.n.qualifying ? "   ·   Qualifying " + root.kickoff(nextCol.n.qualifying) : "")
                color: Commons.Color.accent; font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true
              }
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(10)
            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)
              PanelSectionHeader { text: "LAST RACE"; foreground: root.fg; fontFamily: root.font }
              Text { width: parent.width; text: ((root.f1.last || {}).name || ""); color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; elide: Text.ElideRight }
              Repeater {
                model: (root.f1.last || {}).podium || []
                delegate: Text { required property var modelData; text: modelData; color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption }
              }
            }
            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)
              PanelSectionHeader { text: "DRIVERS' STANDINGS"; foreground: root.fg; fontFamily: root.font }
              Repeater {
                model: root.f1.standings || []
                delegate: Text { required property var modelData; text: modelData; color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption }
              }
            }
          }
          Text {
            text: "You get a reminder 30 minutes before each race."
            color: Qt.darker(root.fg, 1.8); font.family: root.font; font.pixelSize: Style.font.caption
          }
        }

        // ---------- Live, cricket and the ESPN sports ----------
        Flickable {
          id: list
          visible: root.current !== "f1"
          width: parent.width
          height: Math.min(listCol.implicitHeight, Style.space(480))
          contentHeight: listCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: listCol
            width: list.width
            spacing: Style.space(6)

            Repeater {
              model: root.sections
              delegate: Column {
                id: section
                required property var modelData
                width: listCol.width
                spacing: Style.space(6)
                visible: section.modelData.cards.length > 0 || section.modelData.empty !== ""

                PanelSectionHeader {
                  visible: section.modelData.title !== ""
                  text: section.modelData.title
                  foreground: root.fg; fontFamily: root.font
                }
                Repeater {
                  model: section.modelData.cards
                  delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: section.width
                    implicitHeight: cCol.implicitHeight + Style.space(14)
                    radius: Style.cornerRadius
                    color: cArea.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
                                               : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, card.modelData.mine ? 0.08 : 0.04)
                    border.width: card.modelData.mine && card.modelData.hot ? 1 : 0
                    border.color: Commons.Color.accent

                    MouseArea {
                      id: cArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: card.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: { if (card.modelData.url) { Quickshell.execDetached(["xdg-open", card.modelData.url]); root.close() } }
                    }

                    Column {
                      id: cCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(3)

                      Row {
                        spacing: Style.space(6)
                        Rectangle {
                          id: badge
                          visible: card.modelData.badge !== ""
                          width: badgeText.implicitWidth + Style.space(8); height: badgeText.implicitHeight + 2
                          radius: height / 2
                          color: card.modelData.hot ? "#e5484d" : Qt.darker(root.fg, 2.2)
                          anchors.verticalCenter: parent.verticalCenter
                          Text { id: badgeText; anchors.centerIn: parent; text: card.modelData.badge; color: "white"; font.family: root.font; font.pixelSize: Style.font.caption - 1; font.bold: true }
                        }
                        Text {
                          text: card.modelData.header
                          color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          width: cCol.width - (badge.visible ? badge.width + Style.space(6) : 0)
                        }
                      }
                      Text {
                        visible: card.modelData.title !== ""
                        width: cCol.width
                        text: card.modelData.title
                        color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                        elide: Text.ElideRight
                      }
                      Repeater {
                        model: card.modelData.rows
                        delegate: Item {
                          required property var modelData
                          width: cCol.width
                          implicitHeight: rName.implicitHeight
                          Text {
                            id: rScore
                            anchors.right: parent.right
                            text: modelData.score
                            color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                          }
                          Text {
                            id: rName
                            width: parent.width - rScore.implicitWidth - Style.space(10)
                            text: modelData.name + (modelData.win ? "  ✓" : "")
                            elide: Text.ElideRight
                            color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                          }
                        }
                      }
                      Text {
                        visible: card.modelData.foot !== ""
                        width: cCol.width
                        wrapMode: Text.Wrap
                        text: card.modelData.foot
                        color: card.modelData.accent ? Commons.Color.accent : Qt.darker(root.fg, 1.4)
                        font.family: root.font; font.pixelSize: Style.font.caption; font.bold: card.modelData.accent
                      }
                    }
                  }
                }
                Text {
                  visible: section.modelData.cards.length === 0
                  width: section.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: Style.space(6); bottomPadding: Style.space(6)
                  text: section.modelData.empty
                  color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Text {
              width: listCol.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: (root.current === "cricket" ? "Scores from Cricbuzz" : root.current === "live" ? "Cricbuzz · ESPN · Jolpica" : "Scores from ESPN") + " · click a card for details · h/l switch tabs"
              color: Qt.darker(root.fg, 1.9); font.family: root.font; font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
