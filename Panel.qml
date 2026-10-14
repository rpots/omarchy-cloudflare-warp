import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.rui-pedro-silva.cloudflare-warp"
  ipcTarget: moduleName
  manageIpc: false

  property int cursorIndex: -1
  property bool cursorActive: false
  property string confirmAction: ""

  readonly property color foreground: root.bar ? root.bar.foreground : Color.popups.text
  readonly property color background: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color iconDim: Util.alpha(foreground, 0.55)
  readonly property bool iconConnected: warp.state === "connected" && warp.connected
  readonly property bool iconPulse: warp.state === "checking" || warp.state === "connecting" || warp.actionBusy
  readonly property bool iconUrgent: ["missing-client", "daemon-down", "unregistered", "error", "no-network", "unknown"].indexOf(warp.state) !== -1
  readonly property string iconStatus: warp.state === "checking" || warp.state === "connecting" ? "connecting"
    : (iconUrgent ? "urgent" : (iconConnected ? "connected" : "disconnected"))
  readonly property color barIconColor: iconStatus === "connected" || iconStatus === "connecting" ? foreground : iconDim
  // On a transparent bar the shell picks barForeground from the wallpaper
  // (theme text or its contrast color), so the bar icon must follow it rather
  // than the fixed theme foreground. The badge cutout takes the opposite color.
  readonly property color barIconForeground: root.barForeground
  readonly property color barIconDim: Util.alpha(barIconForeground, 0.55)
  readonly property color barIconStateColor: iconStatus === "connected" || iconStatus === "connecting" ? barIconForeground : barIconDim
  readonly property color barIconBackground: {
    if (!root.bar) return Color.bar.background
    if (!root.bar.transparent) return root.bar.background
    var fg = root.barForeground
    var a = root.bar.foreground
    var b = Color.background
    function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    return Math.abs(luma(a) - luma(fg)) >= Math.abs(luma(b) - luma(fg)) ? a : b
  }
  readonly property bool termsAcceptanceRequired: warp.termsRequired
  readonly property bool registrationRequired: warp.state === "unregistered" || warp.termsRequired

  readonly property string recoveryAction: {
    if (warp.canStartDaemon) return "start-daemon"
    if (warp.canRegister) return "register"
    return ""
  }
  readonly property bool configAvailable: warp.operational && warp.state !== "unknown"
    && warp.registrationKnown && warp.settingsKnown && !warp.managed
  readonly property bool configEnabled: configAvailable && !warp.actionBusy
  readonly property int targetCount: recoveryAction !== "" ? 1 : (warp.operational ? (configAvailable ? 4 : 1) : 0)
  readonly property bool dropdownOpen: modeDropdown.popupOpen || protocolDropdown.popupOpen || familiesDropdown.popupOpen
  readonly property bool familiesActive: warp.mode !== "proxy" && warp.mode !== "tunnel_only"
  readonly property bool protocolActive: warp.mode !== "doh" && warp.mode !== "dot"

  readonly property var modeOptions: {
    var options = [
      { value: "warp", label: "WARP · Traffic + DNS (UDP)" },
      { value: "doh", label: "DoH · DNS only (HTTPS)" },
      { value: "warp+doh", label: "WARP + DoH · Traffic + DNS (HTTPS)" },
      { value: "dot", label: "DoT · DNS only (TLS)" },
      { value: "warp+dot", label: "WARP + DoT · Traffic + DNS (TLS)" }
    ]
    if (warp.protocol === "MASQUE") options.push({ value: "proxy", label: "Local proxy · Apps you configure" })
    options.push({ value: "tunnel_only", label: "Traffic only · DNS unchanged" })
    return options
  }
  readonly property var protocolOptions: warp.mode === "proxy"
    ? [{ value: "MASQUE", label: "MASQUE (required for Local proxy)" }]
    : [
        { value: "MASQUE", label: "MASQUE (recommended)" },
        { value: "WireGuard", label: "WireGuard (legacy)" }
      ]
  readonly property var familiesOptions: [
    { value: "off", label: "Off" },
    { value: "malware", label: "Block malware" },
    { value: "full", label: "Block malware + adult content" }
  ]

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  Service {
    id: warp
    settings: root.settings
    pollingPaused: root.confirmAction !== ""
  }

  Component {
    id: barCloudComponent
    Item {
      CloudIcon {
        anchors.centerIn: parent
        iconSize: Style.bar.iconCanvas
        color: root.barIconStateColor
        indicatorColor: root.barIconForeground
        dimColor: root.barIconDim
        badgeColor: root.urgent
        backgroundColor: root.barIconBackground
        fontFamily: root.fontFamily
        status: root.iconStatus
        pulse: root.iconPulse
      }
    }
  }

  function heroTitle() {
    if (warp.state === "missing-client") return "Cloudflare WARP"
    if (warp.state === "daemon-down") return "WARP service stopped"
    if (registrationRequired) return "Registration required"
    if (warp.actionStatus !== "") return warp.actionStatus.replace(/…$/, "")
    if (warp.state === "connected") return "WARP connected"
    if (warp.state === "disconnected") return "WARP disconnected"
    if (warp.state === "connecting") return "WARP is changing state"
    if (warp.state === "no-network") return "Network unavailable"
    return "Cloudflare WARP"
  }

  function heroMeta() {
    if (warp.actionStatus !== "") return warp.actionStatus.replace(/…$/, "").toUpperCase()
    if (warp.state === "missing-client") return "CLIENT REQUIRED"
    if (warp.state === "daemon-down") return "SERVICE NOT RUNNING"
    if (registrationRequired) return "REGISTRATION REQUIRED"
    if (warp.state === "connected") return "CONNECTED"
    if (warp.state === "disconnected") return "DISCONNECTED"
    if (warp.state === "connecting" || warp.actionBusy) return "WORKING"
    if (warp.state === "no-network") return "OFFLINE"
    return String(warp.state || "unknown").toUpperCase()
  }

  function recoveryTitle() {
    return recoveryAction === "start-daemon" ? "Start WARP service" : "Register consumer WARP"
  }

  function recoveryDescription() {
    return recoveryAction === "start-daemon"
      ? "Enable the system service with administrator authentication."
      : "Accept Terms for this widget, check enrollment, then register only if unmanaged."
  }

  function rememberTermsAcceptance() {
    var entry = { id: root.moduleName }
    var current = root.settings || ({})
    for (var key in current) if (key !== "id") entry[key] = current[key]
    entry.termsAccepted = true

    // Apply locally before persisting so Service sees the consent binding on
    // the next event-loop turn even if this widget has no writable bar entry.
    root.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function restoreModeBinding() {
    modeDropdown.value = Qt.binding(function() { return warp.mode })
  }

  function restoreProtocolBinding() {
    protocolDropdown.value = Qt.binding(function() { return warp.protocol })
  }

  function restoreFamiliesBinding() {
    familiesDropdown.value = Qt.binding(function() { return warp.families })
  }

  function setCursor(index) {
    if (targetCount <= 0) {
      cursorActive = false
      cursorIndex = -1
      return
    }
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(targetCount - 1, index))
  }

  function ensureCursorVisible() {
    if (!opened || !cursorActive || cursorIndex < 0) return
    var item = null
    if (recoveryAction !== "") item = recoveryRow
    else if (cursorIndex === 0) item = heroHost
    else if (cursorIndex === 1) item = modeDropdown
    else if (cursorIndex === 2) item = protocolDropdown
    else if (cursorIndex === 3) item = familiesDropdown
    if (!item || !item.visible) return
    var point = item.mapToItem(panelContent, 0, 0)
    var margin = Style.spacing.controlGap
    if (point.y - margin < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, point.y - margin)
    else if (point.y + item.height + margin > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height,
        point.y + item.height + margin - panelFlick.height)
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      setCursor(0)
      return
    }
    if (dy !== 0) setCursor(cursorIndex + dy)
    else if (dx !== 0 && cursorIndex > 0) activateCursor()
  }

  function activateCursor() {
    if (!cursorActive || cursorIndex < 0 || warp.busy) return
    if (recoveryAction !== "") {
      requestConfirmation(recoveryAction)
      return
    }
    if (cursorIndex === 0) warp.toggleWarp()
    else if (cursorIndex === 1) modeDropdown.open()
    else if (cursorIndex === 2) protocolDropdown.open()
    else if (cursorIndex === 3) familiesDropdown.open()
  }

  function requestConfirmation(action) {
    confirmAction = action
    confirmation.selectedIndex = 0
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function closeConfirmation() {
    confirmAction = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmRequestedAction() {
    var action = confirmAction
    closeConfirmation()
    if (action === "start-daemon") warp.startDaemon()
    else if (action === "register") {
      rememberTermsAcceptance()
      // Let the settings binding reach Service before it plans any command.
      Qt.callLater(function() { warp.registerConsumer() })
    }
  }

  function close() {
    modeDropdown.close()
    protocolDropdown.close()
    familiesDropdown.close()
    confirmAction = ""
    controller.hide()
  }

  onTargetCountChanged: {
    if (targetCount <= 0) { cursorActive = false; cursorIndex = -1 }
    else if (cursorIndex >= targetCount) cursorIndex = targetCount - 1
  }

  onCursorIndexChanged: Qt.callLater(ensureCursorVisible)

  onDropdownOpenChanged: if (!dropdownOpen && opened && confirmAction === "")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = -1
    confirmAction = ""
    warp.refresh(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { warp.refresh(true); return "ok" }
    function connect(): string { return warp.connect() ? "ok" : "unavailable" }
    function disconnect(): string { return warp.disconnect() ? "ok" : "unavailable" }
    function toggleWarp(): string { return warp.toggleWarp() ? "ok" : "unavailable" }
    function status(): string { return warp.statusJson() }
  }

  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    iconComponent: barCloudComponent
    tooltipText: "Cloudflare WARP · " + root.heroMeta().toLowerCase()
    Accessible.role: Accessible.Button
    Accessible.name: "Cloudflare WARP, " + root.heroMeta().toLowerCase()
    Accessible.description: warp.actionStatus !== ""
      ? warp.actionStatus
      : (warp.operational
          ? "Opens WARP controls. Right click " + (warp.connected ? "disconnects" : "connects")
            + " WARP. Middle click refreshes status."
          : "Opens WARP setup and recovery controls. Middle click refreshes status.")
    Accessible.onPressAction: root.toggle()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (!warp.toggleWarp()) root.open()
      }
      else if (buttonCode === Qt.MiddleButton) warp.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(panelContent.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOpen || root.confirmAction !== ""
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "t" && warp.operational) warp.toggleWarp()
        else if (key === "r") { warp.actionError = ""; warp.refresh(true) }
      }
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: panelContent.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: panelContent
        width: panelFlick.width
        spacing: Style.spacing.panelGap

      Item {
        id: heroHost
        width: parent.width
        implicitHeight: hero.implicitHeight

        PanelHero {
          id: hero
          width: parent.width
          title: root.heroTitle()
          meta: root.heroMeta()
          detail: warp.locked ? "LOCKED" : (warp.managed ? "MANAGED" : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          // CloudIcon already applies the state-specific theme color. Keep the
          // wrapper opaque so disconnected and urgent badge marks are not
          // dimmed a second time by PanelHero.
          iconOpacity: 1.0
          iconComponent: Component {
            CloudIcon {
              iconSize: Style.font.display
              color: root.barIconColor
              indicatorColor: root.foreground
              dimColor: root.iconDim
              badgeColor: root.urgent
              backgroundColor: root.background
              fontFamily: root.fontFamily
              status: root.iconStatus
              pulse: root.iconPulse
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: warp.operational
              checked: warp.connected
              busy: warp.actionBusy || warp.refreshing || warp.state === "connecting"
              interactive: !(warp.locked && warp.connected)
              hasCursor: root.cursorActive && root.cursorIndex === 0
              foreground: hero.foreground
              onHovered: function(hovered) { if (hovered) root.setCursor(0) }
              onToggled: warp.toggleWarp()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: warp.locked && warp.connected ? "Disconnect is locked by policy"
                  : (warp.connected ? "Disconnect WARP" : "Connect WARP")
                fontFamily: root.fontFamily
              }
            }
          }
        }
      }

      Text {
        readonly property bool showStatusFailure: ["no-network", "error", "unknown"].indexOf(warp.state) !== -1
        visible: warp.actionStatus !== "" || warp.actionError !== "" || (showStatusFailure && !root.termsAcceptanceRequired)
        width: parent.width
        text: warp.actionStatus !== "" ? warp.actionStatus
          : (warp.actionError !== "" ? warp.actionError : warp.statusError)
        color: warp.actionStatus !== "" ? root.dim : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      CursorSurface {
        id: recoveryRow
        visible: root.recoveryAction !== ""
        width: parent.width
        implicitHeight: recoveryText.implicitHeight + Style.spacing.rowPaddingX
        hasCursor: root.cursorActive && root.cursorIndex === 0
        foreground: root.foreground

        Column {
          id: recoveryText
          anchors.left: parent.left
          anchors.right: recoveryChevron.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.spacing.rowPaddingX
          anchors.rightMargin: Style.spacing.controlGap
          spacing: Style.spacing.labelGap

          Text {
            width: parent.width
            text: root.recoveryTitle()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.recoveryDescription()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          id: recoveryChevron
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.rowPaddingX
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          enabled: !warp.busy
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse) root.setCursor(0)
          onClicked: root.requestConfirmation(root.recoveryAction)
        }
      }

      CursorSurface {
        visible: warp.state === "missing-client"
        width: parent.width
        implicitHeight: requiredText.implicitHeight + Style.spacing.rowPaddingX
        foreground: root.foreground

        Column {
          id: requiredText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.spacing.rowPaddingX
          spacing: Style.spacing.labelGap
          Text {
            width: parent.width
            text: "cloudflare-warp-bin is required"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: "Cloudflare does not publish an Arch package. We recommend the community-maintained AUR package."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      CursorSurface {
        visible: root.registrationRequired && root.recoveryAction === "" && !warp.actionBusy
        width: parent.width
        implicitHeight: registrationText.implicitHeight + Style.spacing.rowPaddingX
        foreground: root.foreground

        Column {
          id: registrationText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.spacing.rowPaddingX
          spacing: Style.spacing.labelGap
          Text {
            width: parent.width
            text: warp.managedEnrollmentConfigured ? "Managed enrollment detected" : "Registration needs attention"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: warp.refreshing
              ? "Checking whether consumer registration is safe on this device…"
              : (warp.managedEnrollmentConfigured
                  ? "Organization enrollment is outside this plugin’s scope. Complete it with your administrator."
                  : (root.termsAcceptanceRequired
                      ? "Cloudflare requires Terms acceptance before first registration. The plugin will offer consumer registration here after it verifies the client state."
                      : "The plugin could not verify WARP’s MDM configuration. Refresh and retry; no registration was attempted."))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      PanelSeparator {
        visible: warp.operational
        foreground: root.foreground
      }

      Column {
        visible: warp.operational
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          implicitHeight: Math.max(configHeader.implicitHeight, managedLabel.implicitHeight)
          PanelSectionHeader {
            id: configHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "CONFIGURATION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          PanelSectionHeader {
            id: managedLabel
            visible: warp.managed
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "MANAGED · READ ONLY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        Dropdown {
          id: modeDropdown
          width: parent.width
          label: "MODE"
          value: warp.mode
          options: root.modeOptions
          enabled: root.configEnabled
          opacity: enabled ? 1.0 : 0.5
          hasCursor: root.cursorActive && root.cursorIndex === 1
          foreground: root.foreground
          background: root.background
          fontFamily: root.fontFamily
          onHovered: function(hovered) { if (hovered && root.configEnabled) root.setCursor(1) }
          onChanged: function(value) {
            if (value !== warp.mode) warp.setMode(value)
            Qt.callLater(root.restoreModeBinding)
          }
        }

        Text {
          visible: warp.protocol !== "MASQUE"
          width: parent.width
          text: "Local proxy requires MASQUE and becomes available after MASQUE is selected."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Dropdown {
          id: protocolDropdown
          width: parent.width
          label: "TUNNEL PROTOCOL"
          value: warp.protocol
          options: root.protocolOptions
          enabled: root.configEnabled
          opacity: enabled ? 1.0 : 0.5
          hasCursor: root.cursorActive && root.cursorIndex === 2
          foreground: root.foreground
          background: root.background
          fontFamily: root.fontFamily
          onHovered: function(hovered) { if (hovered && root.configEnabled) root.setCursor(2) }
          onChanged: function(value) {
            if (value !== warp.protocol) warp.setProtocol(value)
            Qt.callLater(root.restoreProtocolBinding)
          }
        }

        Text {
          visible: !root.protocolActive
          width: parent.width
          text: "Stored for later; tunnel protocol is not active in a DNS-only mode."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Dropdown {
          id: familiesDropdown
          width: parent.width
          label: "FAMILIES FILTERING"
          value: warp.families
          options: root.familiesOptions
          enabled: root.configEnabled
          opacity: enabled ? 1.0 : 0.5
          hasCursor: root.cursorActive && root.cursorIndex === 3
          foreground: root.foreground
          background: root.background
          fontFamily: root.fontFamily
          onHovered: function(hovered) { if (hovered && root.configEnabled) root.setCursor(3) }
          onChanged: function(value) {
            if (value !== warp.families) warp.setFamilies(value)
            Qt.callLater(root.restoreFamiliesBinding)
          }
        }

        Text {
          visible: !root.familiesActive
          width: parent.width
          text: warp.mode === "proxy"
            ? "Not active in Local proxy mode. Only apps configured for the local proxy use WARP."
            : "Not active in Traffic-only mode because DNS remains outside WARP."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: warp.managed
          width: parent.width
          text: "Connection and DNS settings are controlled by your organization."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: warp.operational && !warp.settingsKnown
          width: parent.width
          text: "Configuration is unavailable until warp-cli returns a complete, recognized settings snapshot."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: warp.locked
          width: parent.width
          text: "Switch Locked is active. Connecting is allowed, but disconnecting is controlled by policy."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Text {
        width: parent.width
        text: "↑/↓ move · Enter select · t toggle · r refresh · Tab switch panel"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
      }
    }

    Item {
      id: confirmKeys
      anchors.fill: parent
      visible: root.confirmAction !== ""
      focus: visible
      z: 20
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (confirmation.handleKey(event)) event.accepted = true
      }
    }

    PanelConfirmDialog {
      id: confirmation
      anchors.fill: parent
      z: 10
      opened: root.confirmAction !== ""
      title: root.confirmAction === "start-daemon" ? "Start WARP service?" : "Accept Terms and register?"
      message: root.confirmAction === "start-daemon"
        ? "Enables warp-svc.service and opens the system authentication dialog."
        : "Confirming accepts Cloudflare’s Terms and remembers that choice for this widget, adding --accept-tos to future WARP commands. It then checks enrollment and registers only if unmanaged; managed users should cancel."
      confirmText: root.confirmAction === "start-daemon" ? "Start" : "Accept"
      background: root.background
      foreground: root.foreground
      scrim: Util.alpha(root.background, 0.78)
      accent: Color.accent
      fontFamily: root.fontFamily
      onCanceled: root.closeConfirmation()
      onConfirmed: root.confirmRequestedAction()
    }
  }
}
