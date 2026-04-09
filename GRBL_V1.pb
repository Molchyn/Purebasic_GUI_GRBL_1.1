; ============================================
;   PureBasic GRBL v1.1 Controller (Corrected)
;   Fixed realtime commands + improved buffers
;   Based on official GRBL v1.1 Commands
; ============================================
CompilerIf #PB_Compiler_Thread = 0
  CompilerError "Use Option Threadsafe!"
CompilerEndIf
EnableExplicit

#CRLF$ = Chr(13) + Chr(10)
#APP_TITLE = "GRBL v1.1 Controller"

; ============================================
;   GADGET ENUMERATION (unchanged)
; ============================================
Enumeration
  ; Main window
  #Window_Main
  
  ; Menu
  #Menu_Main
  
  ; Port panel
  #Combo_Port
  #Button_RefreshPorts
  #Button_ConnectToggle
  #Canvas_PortStatus
  #Text_StatusBar
  #Text_MachinePos
  #Text_WorkPos
  #Text_MachineState
  
  ; Tab container
  #Tab_Main
  
  ; --- Tab 0: Console ---
  #Editor_Console
  #Edit_ConsoleInput
  #Button_ConsoleSend
  #Button_ConsoleClear
  #Check_AutoScroll
  
  ; --- Tab 1: Jog / Motion ---
  #Button_JogXPlus
  #Button_JogXMinus
  #Button_JogYPlus
  #Button_JogYMinus
  #Button_JogZPlus
  #Button_JogZMinus
  #Button_JogStop
  #Button_HomeAll
  #Button_HomeX
  #Button_HomeY
  #Button_HomeZ
  #Button_ZeroAll
  #Button_ZeroX
  #Button_ZeroY
  #Button_ZeroZ
  #Button_GoToZero
  #Spin_JogStep
  #Spin_JogFeed
  #Text_JogStep
  #Text_JogFeed
  #Combo_JogUnit
  #Button_SoftReset
  #Button_FeedHold
  #Button_CycleStart
  #Button_UnlockAlarm
  
  ; --- Tab 2: Settings ---
  #List_Settings
  #Edit_SettingFilter
  #Button_SettingsRead
  #Button_SettingWrite
  #Edit_SettingVal
  #Text_SettingVal
  #Button_SettingsSaveFile
  #Button_SettingsLoadFile
  #Check_SettingFilter
  
  ; --- Tab 3: Probing ---
  #Button_ProbeZ
  #Button_ProbeXY
  #Spin_ProbeSeek
  #Spin_ProbeFeed
  #Spin_ProbeDepth
  #Spin_ProbePlateThick
  #Text_ProbeSeek
  #Text_ProbeFeed
  #Text_ProbeDepth
  #Text_ProbePlate
  #Editor_ProbeResult
  #Button_ProbeClear
  #Check_ProbeAutoZero
  
  ; --- Tab 4: Overrides ---
  #Button_OvFeedPlus10
  #Button_OvFeedMinus10
  #Button_OvFeedPlus1
  #Button_OvFeedMinus1
  #Button_OvFeedReset
  #Button_OvRapidHigh
  #Button_OvRapidMed
  #Button_OvRapidLow
  #Button_OvSpindlePlus10
  #Button_OvSpindleMinus10
  #Button_OvSpindlePlus1
  #Button_OvSpindleMinus1
  #Button_OvSpindleReset
  #Button_OvFloodToggle
  #Button_OvMistToggle
  #Text_OvFeedVal
  #Text_OvRapidVal
  #Text_OvSpindleVal
  
  ; --- Tab 5: EEPROM / Info ---
  #Editor_EEPROMInfo
  #Button_GetBuildInfo
  #Button_GetStartup
  #Button_GetCheckMode
  #Button_ToggleCheckMode
  #Button_GetParserState
  #Button_ViewParams
  #Button_ViewBuildOptions
  
  ; --- Tab 6: File / GCode ---
  #Editor_GCode
  #Button_GCodeOpen
  #Button_GCodeSend
  #Button_GCodeStop
  #ProgressBar_GCode
  #Text_GCodeStatus
  #Check_GCodeDryRun
  #Button_GCodeClear
  
  ; Timers
  #Timer_Status
  #Timer_GUI
  
  ; Log window
  #Window_Log
  #Editor_Log
  #Button_HideLog
  #Button_ShowLog
  #Button_SaveLog
EndEnumeration

; ============================================
;   STRUCTURES & GLOBALS (unchanged)
; ============================================
Structure GRBLStatus
  state.s           ; Idle, Run, Hold, Jog, Alarm, Door, Check, Home, Sleep
  mx.d : my.d : mz.d; machine position
  wx.d : wy.d : wz.d; work position
  feed.d
  spindle.d
  ov_feed.i
  ov_rapid.i
  ov_spindle.i
  flood.i
  mist.i
  lastUpdate.i
EndStructure

Structure GRBLSetting
  number.i
  value.s
  description.s
EndStructure

Global NewList LogMessages.s()
Global LogMutex.i     = CreateMutex()
Global Mutex.i        = CreateMutex()
Global RawMutex.i     = CreateMutex()
Global StatusMutex.i  = CreateMutex()
Global SettingMutex.i = CreateMutex()

Global NewList PendingCommands.s()
Global NewList RawDataQueue.s()
Global NewList SettingsList.GRBLSetting()

Global SerialPort.i      = -1
Global SerialThreadID.i  = 0
Global GCodeThreadID.i   = 0
Global Running.i         = #False
Global ShutdownSignal.i  = #False
Global quit.i            = #False
Global LogWindowOpen.i   = #False
Global GCodeRunning.i    = #False
Global GCodeStop.i       = #False
Global CheckModeActive.i = #False

Global CurrentStatus.GRBLStatus
Global NewList ProbeResults.s()

; GCode streaming
Global NewList GCodeLines.s()
Global GCodeTotal.i   = 0
Global GCodeSent.i    = 0
Global GCodeAckOk.i   = 0

; Port scan
Global NewList ScannedPorts.s()
Global NewList GRBLPorts.s()
Global ScanMutex.i = CreateMutex()

; ============================================
;   FORWARD DECLARATIONS
; ============================================
Declare AddLog(msg.s, level.s = "INFO")
Declare UpdateLogWindow()
Declare ToggleLogWindow()
Declare HideLogHandler()
Declare SaveLogFile()
Declare SendCommand(cmd.s, priority.i = #False)
Declare SerialThread(Param.i)
Declare RefreshPorts()
Declare ConnectToggleHandler()
Declare ConnectToPort(port.s)
Declare DisconnectPort()
Declare ParseStatusReport(line.s)
Declare ParseSettingsLine(line.s)
Declare ProcessRawQueue()
Declare SafeUpdateGUI()
Declare DrawPortStatus(connected.i, grbl.i)
Declare UpdateStatusBar()
Declare BuildTabConsole(x.i, y.i, w.i, h.i)
Declare BuildTabJog(x.i, y.i, w.i, h.i)
Declare BuildTabSettings(x.i, y.i, w.i, h.i)
Declare BuildTabProbing(x.i, y.i, w.i, h.i)
Declare BuildTabOverrides(x.i, y.i, w.i, h.i)
Declare BuildTabInfo(x.i, y.i, w.i, h.i)
Declare BuildTabGCode(x.i, y.i, w.i, h.i)
Declare SendJog(axis.s, dist.d, feed.d, unit.s)
Declare SendRealtime(byte.i)
Declare ReadSettings()
Declare WriteSelectedSetting()
Declare GCodeThread(Param.i)
Declare StartGCodeStream()
Declare StopGCodeStream()
Declare ResizeMainWindow()
Declare COMGetAvailablePorts(List Ports.s())
Declare ScanPortsForGRBL()
Declare PortScanThread(Param.i)
Declare AppendConsole(text.s)

Declare  ConsoleSendHandler()
Declare  ConsoleInputHandler()
Declare ConsoleClearHandler()
Declare JogXPlusHandler()
Declare JogXMinusHandler()
Declare JogYPlusHandler()
Declare JogYMinusHandler()
Declare JogZPlusHandler()
Declare JogZMinusHandler()
Declare JogStopHandler()
Declare HomeAllHandler()
Declare HomeXHandler()
Declare HomeYHandler()
Declare HomeZHandler()
Declare ZeroAllHandler()
Declare ZeroXHandler()
Declare ZeroYHandler()
Declare ZeroZHandler()
Declare GoToZeroHandler()
Declare SoftResetHandler()
Declare FeedHoldHandler()
Declare CycleStartHandler()
Declare UnlockAlarmHandler()
Declare SettingsReadHandler()
Declare SettingWriteHandler()
Declare SettingsSaveHandler()
Declare SettingsLoadHandler()
Declare SettingsListClickHandler(); Spindle overrides
Declare ProbeZHandler()
Declare ProbeXYHandler()
Declare ProbeClearHandler()
Declare OvFeedP10()
Declare OvFeedM10()
Declare OvFeedP1()
Declare OvFeedM1()
Declare OvFeedReset()
Declare OvRapidHigh()
Declare OvRapidMed()
Declare OvRapidLow()
Declare OvSpindleP10()
Declare OvSpindleM10()
Declare OvSpindleP1()
Declare OvSpindleM1()
Declare OvSpindleReset()
Declare OvFloodToggle()
Declare OvMistToggle()
Declare GetBuildInfoHandler()
Declare GetStartupHandler()
Declare GetParserStateHandler()
Declare ViewParamsHandler()
Declare ViewBuildOptionsHandler()
Declare GetCheckModeHandler()
Declare GCodeOpenHandler()
Declare GCodeSendHandler()
Declare GCodeStopHandler()
Declare GCodeClearHandler()

; #GRBL_OV_FEED_P10 =$91
; #GRBL_OV_FEED_M10 =$92
; #GRBL_OV_FEED_P1  =$93
; #GRBL_OV_FEED_M1  =$94
; #GRBL_OV_FEED_RESET =$95
; #GRBL_OV_RAPID_HIGH =$96
; #GRBL_OV_RAPID_MED  =$97
; #GRBL_OV_RAPID_LOW  =$98
; #GRBL_STATUS_QUERY  =$63
; #GRBL_OV_SPINDLE_P10  =$98
; #GRBL_OV_SPINDLE_M10  =$98
; #GRBL_OV_SPINDLE_P1 =$99
; #GRBL_OV_SPINDLE_M1 =$9A
; #GRBL_OV_SPINDLE_RESET  =$9B
; #GRBL_TOGGLE_FLOOD  =$A0
; #GRBL_TOGGLE_MIST =$A1

; ; ; ; Supported Real-Time Commands
; ; ; ; Command	Symbol	Description
; ; ; ; Status Report	                    ?	Returns current machine state, positions, And settings. Can be used repeatedly To track motion in real-time.
; ; ; ; Cycle Start/Resume	              ~	Resumes motion after a feed hold Or a safety door pause.
; ; ; ; Feed Hold (Pause)	                  !	Immediately pauses motion. This is a controlled stop that retains machine position And can be resumed With ~.
; ; ; ; Soft Reset	          Ctrl+X	Instantly resets Grbl. All operations are stopped, And settings are reloaded. Must unlock With $X afterward.
; ; ; ; Safety Door	          0x84	Tells Grbl the safety door is open. Motion And spindle pause safely. Resumed via door reopen/resume protocol.
; ; ; ; Jog Cancel	          0x85	Immediately cancels any jogging operation in progress.
; ; ; ; Feed Override +10%	  0x90	Increases the feed rate by 10%.
; ; ; ; Feed Override -10%	  0x91	Decreases the feed rate by 10%.
; ; ; ; Feed Override Reset	  0x92	Resets the feed rate To 100%.
; ; ; ; Rapid Override -100% (disable)	  0x93	Disables rapid movement (sets rapid rate To 0%).
; ; ; ; Rapid Override -50%	              0x94	Reduces rapid movement To 50% speed.
; ; ; ; Rapid Override Reset	            0x95	Restores rapid movement To full speed.
; ; ; ; Spindle Speed Override +10%	      0x99	Increases spindle speed by 10%.
; ; ; ; Spindle Speed Override -10%	      0x9A	Decreases spindle speed by 10%.
; ; ; ; Spindle Speed Reset	              0x9B	Resets spindle speed To 100%.
; ; ; ; Toggle Spindle Stop	              0x9E	Stops Or restarts the spindle depending on its current state.
; ; ; ; Toggle Flood Coolant	            0xA0	Turns flood coolant on Or off.
; ; ; ; Toggle Mist Coolant	              0xA1	Turns mist coolant on Or off.
; ; ; ; Common Use Cases
; ; ; ; Pause a job: Use ! To pause mid-cut safely.
; ; ; ; 
; ; ; ; Check position: Send ? during a job To get real-time coordinates.
; ; ; ; 
; ; ; ; Emergency recovery: Use Ctrl+X For a fast reset in Case of failure Or crash.
; ; ; ; 
; ; ; ; Adjust speeds: Use overrides To fine-tune feeds/spindle during a run.
; ; ; ; 


; ============================================
;   CORRECTED REALTIME COMMANDS (GRBL v1.1)
; ============================================
; Official values from https://github.com/gnea/grbl/wiki/Grbl-v1.1-Commands

#GRBL_SOFT_RESET        = $18   ; Ctrl-X
#GRBL_FEED_HOLD         = $21   ; !
#GRBL_CYCLE_START       = $7E   ; ~
#GRBL_STATUS_QUERY      = $3F   ; ?
#GRBL_JOG_CANCEL        = $85

; Feed Overrides
#GRBL_OV_FEED_P10       = $90   ; +10%
#GRBL_OV_FEED_M10       = $91   ; -10%
#GRBL_OV_FEED_P1        = $92   ; +1%
#GRBL_OV_FEED_M1        = $93   ; -1%
#GRBL_OV_FEED_RESET     = $94   ; Reset to 100%

; Rapid Overrides
#GRBL_OV_RAPID_HIGH     = $95   ; 100%
#GRBL_OV_RAPID_MED      = $96   ; 50%
#GRBL_OV_RAPID_LOW      = $97   ; 25%

; Spindle Overrides
#GRBL_OV_SPINDLE_RESET  = $99
#GRBL_OV_SPINDLE_P10    = $9A   ; +10%
#GRBL_OV_SPINDLE_M10    = $9B   ; -10%
#GRBL_OV_SPINDLE_P1     = $9C   ; +1%
#GRBL_OV_SPINDLE_M1     = $9D   ; -1%

; Coolant
#GRBL_TOGGLE_FLOOD      = $A0
#GRBL_TOGGLE_MIST       = $A1

; ============================================
;   GRBL SETTING DESCRIPTIONS (unchanged)
; ============================================
Global Dim GRBLSettingDesc.s(132)

Procedure InitSettingDescriptions()
  GRBLSettingDesc(0)  = "$0 - Step pulse time (µs)"
  GRBLSettingDesc(1)  = "$1 - Step idle delay (ms)"
  GRBLSettingDesc(2)  = "$2 - Step port invert (mask)"
  GRBLSettingDesc(3)  = "$3 - Direction port invert (mask)"
  GRBLSettingDesc(4)  = "$4 - Step enable invert (bool)"
  GRBLSettingDesc(5)  = "$5 - Limit pins invert (bool)"
  GRBLSettingDesc(6)  = "$6 - Probe pin invert (bool)"
  GRBLSettingDesc(10) = "$10 - Status report options (mask)"
  GRBLSettingDesc(11) = "$11 - Junction deviation (mm)"
  GRBLSettingDesc(12) = "$12 - Arc tolerance (mm)"
  GRBLSettingDesc(13) = "$13 - Report in inches (bool)"
  GRBLSettingDesc(20) = "$20 - Soft limits (bool)"
  GRBLSettingDesc(21) = "$21 - Hard limits (bool)"
  GRBLSettingDesc(22) = "$22 - Homing cycle (bool)"
  GRBLSettingDesc(23) = "$23 - Homing direction invert (mask)"
  GRBLSettingDesc(24) = "$24 - Homing locate feed (mm/min)"
  GRBLSettingDesc(25) = "$25 - Homing search seek (mm/min)"
  GRBLSettingDesc(26) = "$26 - Homing switch debounce (ms)"
  GRBLSettingDesc(27) = "$27 - Homing switch pull-off (mm)"
  GRBLSettingDesc(30) = "$30 - Max spindle speed (RPM)"
  GRBLSettingDesc(31) = "$31 - Min spindle speed (RPM)"
  GRBLSettingDesc(32) = "$32 - Laser mode (bool)"
  GRBLSettingDesc(100) = "$100 - X-axis steps/mm"
  GRBLSettingDesc(101) = "$101 - Y-axis steps/mm"
  GRBLSettingDesc(102) = "$102 - Z-axis steps/mm"
  GRBLSettingDesc(110) = "$110 - X-axis max rate (mm/min)"
  GRBLSettingDesc(111) = "$111 - Y-axis max rate (mm/min)"
  GRBLSettingDesc(112) = "$112 - Z-axis max rate (mm/min)"
  GRBLSettingDesc(120) = "$120 - X-axis acceleration (mm/sec²)"
  GRBLSettingDesc(121) = "$121 - Y-axis acceleration (mm/sec²)"
  GRBLSettingDesc(122) = "$122 - Z-axis acceleration (mm/sec²)"
  GRBLSettingDesc(130) = "$130 - X-axis max travel (mm)"
  GRBLSettingDesc(131) = "$131 - Y-axis max travel (mm)"
  GRBLSettingDesc(132) = "$132 - Z-axis max travel (mm)"
EndProcedure

; ============================================
;   LOGGING, PORT ENUMERATION, SCAN THREAD (unchanged)
; ============================================
Procedure AddLog(msg.s, level.s = "INFO")
  If TryLockMutex(LogMutex)
    AddElement(LogMessages())
    LogMessages() = FormatDate("%hh:%ii:%ss", Date()) + " [" + level + "] " + msg
    While ListSize(LogMessages()) > 2000
      FirstElement(LogMessages())
      DeleteElement(LogMessages())
    Wend
    UnlockMutex(LogMutex)
  EndIf
EndProcedure

; ... (UpdateLogWindow, ToggleLogWindow, HideLogHandler, SaveLogFile remain unchanged)
Procedure UpdateLogWindow()
  If LogWindowOpen And IsWindow(#Window_Log)
    Protected txt.s = ""
    LockMutex(LogMutex)
    ForEach LogMessages() : txt + LogMessages() + #CRLF$ : Next
    UnlockMutex(LogMutex)
    SetGadgetText(#Editor_Log, txt)
    SendMessage_(GadgetID(#Editor_Log), #EM_SETSEL, -1, -1)
    SendMessage_(GadgetID(#Editor_Log), #EM_SCROLLCARET, 0, 0)
  EndIf
EndProcedure

Procedure ToggleLogWindow()
  If LogWindowOpen And IsWindow(#Window_Log)
    CloseWindow(#Window_Log)
    LogWindowOpen = #False
    SetGadgetText(#Button_ShowLog, "Show Log")
  Else
    If OpenWindow(#Window_Log, 200, 200, 700, 450, "System Log",
                  #PB_Window_SystemMenu | #PB_Window_SizeGadget)
      LogWindowOpen = #True
      SetGadgetText(#Button_ShowLog, "Hide Log")
      EditorGadget(#Editor_Log, 5, 5, 690, 400, #PB_Editor_ReadOnly)
      ButtonGadget(#Button_HideLog, 5, 415, 100, 25, "Close")
      BindGadgetEvent(#Button_HideLog, @HideLogHandler())
      UpdateLogWindow()
    EndIf
  EndIf
EndProcedure

Procedure HideLogHandler()
  If LogWindowOpen And IsWindow(#Window_Log)
    CloseWindow(#Window_Log)
    LogWindowOpen = #False
    SetGadgetText(#Button_ShowLog, "Show Log")
  EndIf
EndProcedure

Procedure SaveLogFile()
  Protected fn.s = "GRBL_Log_" + FormatDate("%yyyy%mm%dd_%hh%ii%ss", Date()) + ".txt"
  Protected f.i = OpenFile(#PB_Any, fn)
  If f
    LockMutex(LogMutex)
    ForEach LogMessages() : WriteStringN(f, LogMessages()) : Next
    UnlockMutex(LogMutex)
    CloseFile(f)
    MessageRequester("Saved", "Log saved: " + fn, #PB_MessageRequester_Info)
  EndIf
EndProcedure

; infratec add for linux mac...
Procedure COMGetAvailablePorts()
  Protected NewList COMPortNameList.s()
  Protected i.i, Directory.i, Com.i
  
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    For i = 1 To #COMMaxPorts
      AddElement(COMPortNameList())
      COMPortNameList() = "COM" + Str(i)
    Next i
  CompilerEndIf
  
  CompilerIf #PB_Compiler_OS = #PB_OS_Linux
    Directory = ExamineDirectory(#PB_Any, "/dev", "ttyUSB*")
    If Directory
      While NextDirectoryEntry(Directory)
        AddElement(COMPortNameList())
        COMPortNameList() = "/dev/" + DirectoryEntryName(Directory)
      Wend
      FinishDirectory(Directory)
    EndIf
  CompilerEndIf
  
  CompilerIf #PB_Compiler_OS = #PB_OS_MacOS
    Directory = ExamineDirectory(#PB_Any, "/dev", "tty.usbserial*")
    If Directory
      While NextDirectoryEntry(Directory)
        AddElement(COMPortNameList())
        COMPortNameList() = "/dev/" + DirectoryEntryName(Directory)
      Wend
      FinishDirectory(Directory)
    EndIf
  CompilerEndIf
  
  ForEach COMPortNameList()
    Com = OpenSerialPort(#PB_Any, COMPortNameList(), 9600, #PB_SerialPort_NoParity, 8, 1, #PB_SerialPort_NoHandshake, 1, 1)
    If Com
      AddElement(COMUsablePorts())
      COMUsablePorts() = COMPortNameList()
      CloseSerialPort(Com)
    EndIf
  Next
  FreeList(COMPortNameList())  
EndProcedure


; PortScanThread, ScanPortsForGRBL, RefreshPorts, DrawPortStatus remain the same
Procedure PortScanThread(Param.i)
  Protected NewList localPorts.s()
  LockMutex(ScanMutex)
  ForEach ScannedPorts() : AddElement(localPorts()) : localPorts() = ScannedPorts() : Next
  UnlockMutex(ScanMutex)
  
  ForEach localPorts()
    Protected port.s = localPorts()
    Protected h.i = OpenSerialPort(#PB_Any, port, 115200,
                                   #PB_SerialPort_NoParity, 8, 1,
                                   #PB_SerialPort_NoHandshake, 64, 64)
    If h = 0 : Continue : EndIf
    
    ; Send soft reset then "$" to elicit GRBL response
    Protected resetByte.a = #GRBL_SOFT_RESET
    WriteSerialPortData(h, @resetByte, 1)
    Delay(300)
    WriteSerialPortString(h, "$" + #CRLF$)
    Delay(600)
    
    Protected avail.i = AvailableSerialPortInput(h)
    Protected found.i = #False
    If avail > 0
      Protected *buf = AllocateMemory(512)
      Protected rd.i = ReadSerialPortData(h, *buf, avail)
      If rd > 0
        Protected resp.s = PeekS(*buf, rd, #PB_Ascii)
        ; GRBL responds with "Grbl" banner or "$" help or "ok"
        If FindString(resp, "Grbl") Or FindString(resp, "$0") Or
           FindString(resp, "ok") Or FindString(resp, "[HLP:")
          found = #True
        EndIf
      EndIf
      FreeMemory(*buf)
    EndIf
    CloseSerialPort(h)
    
    If found
      LockMutex(ScanMutex)
      AddElement(GRBLPorts()) : GRBLPorts() = port
      UnlockMutex(ScanMutex)
      AddLog("GRBL detected on " + port, "INFO")
    EndIf
  Next
  AddLog("Port scan complete", "INFO")
EndProcedure

Procedure ScanPortsForGRBL()
  LockMutex(ScanMutex)
  ClearList(ScannedPorts())
  ClearList(GRBLPorts())
  COMGetAvailablePorts(ScannedPorts())
  UnlockMutex(ScanMutex)
  If ListSize(ScannedPorts()) = 0
    AddLog("No serial ports found", "WARNING")
    ProcedureReturn
  EndIf
  AddLog("Scanning " + Str(ListSize(ScannedPorts())) + " port(s) for GRBL...", "INFO")
  CreateThread(@PortScanThread(), 0)
EndProcedure

; ============================================
;   REFRESH PORTS UI
; ============================================
Procedure RefreshPorts()
  ClearGadgetItems(#Combo_Port)
  Protected NewList ports.s()
  COMGetAvailablePorts(ports())
  ForEach ports()
    AddGadgetItem(#Combo_Port, -1, ports())
  Next
  If CountGadgetItems(#Combo_Port) > 0
    SetGadgetState(#Combo_Port, 0)
  EndIf
  DrawPortStatus(#False, #False)
  ScanPortsForGRBL()
  AddLog("Port list refreshed (" + Str(CountGadgetItems(#Combo_Port)) + " ports)", "INFO")
EndProcedure

; ============================================
;   DRAW PORT STATUS INDICATOR
; ============================================
Procedure DrawPortStatus(connected.i, grbl.i)
  If Not IsGadget(#Canvas_PortStatus) : ProcedureReturn : EndIf
  If StartDrawing(CanvasOutput(#Canvas_PortStatus))
    Protected col.i
    If connected And grbl
      col = RGB(0, 220, 60)       ; bright green = GRBL confirmed
    ElseIf connected
      col = RGB(255, 165, 0)      ; orange = connected but not confirmed
    Else
      col = RGB(200, 40, 40)      ; red = disconnected
    EndIf
    ; Outer ring
    Circle(10, 10, 9, RGB(30,30,30))
    ; Fill
    FillArea(10, 10, RGB(30,30,30), col)
    ; Highlight
    Circle(7, 7, 3, RGBA(255,255,255,80))
    StopDrawing()
  EndIf
EndProcedure



; ============================================
;   SEND PROCEDURES
; ============================================
Procedure SendCommand(cmd.s, priority.i = #False)
  If SerialPort = -1
    AddLog("Not connected — command ignored: " + cmd, "WARNING")
    ProcedureReturn
  EndIf
  LockMutex(Mutex)
  If priority
    FirstElement(PendingCommands())
    InsertElement(PendingCommands())
    PendingCommands() = cmd
  Else
    AddElement(PendingCommands())
    PendingCommands() = cmd
  EndIf
  UnlockMutex(Mutex)
EndProcedure

Procedure SendRealtime(byte.i)
  If SerialPort = -1 : ProcedureReturn : EndIf
  Protected b.a = byte
  WriteSerialPortData(SerialPort, @b, 1)
EndProcedure

; ============================================
;   PARSERS, SERIAL THREAD, CONNECT/DISCONNECT (mostly unchanged)
; ============================================
; ParseStatusReport, ParseSettingsLine, AppendConsole, ProcessRawQueue remain the same
Procedure ParseStatusReport(line.s)
  ; Format: <State|MPos:x,y,z|WPos:x,y,z|FS:f,s|Ov:fo,ro,so|A:flood/mist>
  ; or:     <State|MPos:x,y,z|WCO:x,y,z|...>
  Protected inner.s = Mid(line, 2, Len(line)-2)  ; strip < >
  Protected field.s, i.i, n.i
  
  LockMutex(StatusMutex)
  n = CountString(inner, "|") + 1
  For i = 1 To n
    field = StringField(inner, i, "|")
    If i = 1
      CurrentStatus\state = field
    ElseIf Left(field, 5) = "MPos:"
      Protected coords.s = Mid(field, 6)
      CurrentStatus\mx = ValD(StringField(coords, 1, ","))
      CurrentStatus\my = ValD(StringField(coords, 2, ","))
      CurrentStatus\mz = ValD(StringField(coords, 3, ","))
    ElseIf Left(field, 5) = "WPos:"
      coords = Mid(field, 6)
      CurrentStatus\wx = ValD(StringField(coords, 1, ","))
      CurrentStatus\wy = ValD(StringField(coords, 2, ","))
      CurrentStatus\wz = ValD(StringField(coords, 3, ","))
    ElseIf Left(field, 3) = "FS:"
      Protected fs.s = Mid(field, 4)
      CurrentStatus\feed    = ValD(StringField(fs, 1, ","))
      CurrentStatus\spindle = ValD(StringField(fs, 2, ","))
    ElseIf Left(field, 3) = "Ov:"
      Protected ov.s = Mid(field, 4)
      CurrentStatus\ov_feed    = Val(StringField(ov, 1, ","))
      CurrentStatus\ov_rapid   = Val(StringField(ov, 2, ","))
      CurrentStatus\ov_spindle = Val(StringField(ov, 3, ","))
    ElseIf Left(field, 2) = "A:"
      Protected acc.s = Mid(field, 3)
      CurrentStatus\flood = Bool(FindString(acc, "F") > 0)
      CurrentStatus\mist  = Bool(FindString(acc, "M") > 0)
    EndIf
  Next
  CurrentStatus\lastUpdate = ElapsedMilliseconds()
  UnlockMutex(StatusMutex)
EndProcedure

; ============================================
;   PARSE SETTINGS LINE  $x=value
; ============================================
Procedure ParseSettingsLine(line.s)
  If Left(line, 1) <> "$" : ProcedureReturn : EndIf
  Protected eqPos.i = FindString(line, "=")
  If eqPos < 2 : ProcedureReturn : EndIf
  Protected num.i = Val(Mid(line, 2, eqPos - 2))
  Protected val.s = Mid(line, eqPos + 1)
  
  LockMutex(SettingMutex)
  Protected found.i = #False
  ForEach SettingsList()
    If SettingsList()\number = num
      SettingsList()\value = val
      found = #True
      Break
    EndIf
  Next
  If Not found
    AddElement(SettingsList())
    SettingsList()\number = num
    SettingsList()\value  = val
    If num <= 132 And GRBLSettingDesc(num) <> ""
      SettingsList()\description = GRBLSettingDesc(num)
    Else
      SettingsList()\description = "$" + Str(num)
    EndIf
  EndIf
  UnlockMutex(SettingMutex)
EndProcedure

; ============================================
;   APPEND TO CONSOLE (GUI thread only)
; ============================================
Procedure AppendConsole(text.s)
  If Not IsGadget(#Editor_Console) : ProcedureReturn : EndIf
  AddGadgetItem(#Editor_Console, -1, text)
  While CountGadgetItems(#Editor_Console) > 1000
    RemoveGadgetItem(#Editor_Console, 0)
  Wend
  If GetGadgetState(#Check_AutoScroll) = #PB_Checkbox_Checked
    SendMessage_(GadgetID(#Editor_Console), #EM_SETSEL, -1, -1)
    SendMessage_(GadgetID(#Editor_Console), #EM_SCROLLCARET, 0, 0)
  EndIf
EndProcedure

; ============================================
;   PROCESS RAW QUEUE (GUI thread)
; ============================================
Procedure ProcessRawQueue()
  LockMutex(RawMutex)
  If ListSize(RawDataQueue()) = 0
    UnlockMutex(RawMutex)
    ProcedureReturn
  EndIf
  Protected NewList snap.s()
  ForEach RawDataQueue()
    AddElement(snap()) : snap() = RawDataQueue()
  Next
  ClearList(RawDataQueue())
  UnlockMutex(RawMutex)
  
  ForEach snap()
    Protected line.s = snap()
    AppendConsole(line)
    
    ; Route to parsers
    If Left(line, 1) = "<" And Right(line, 1) = ">"
      ParseStatusReport(line)
    ElseIf Left(line, 1) = "$" And FindString(line, "=")
      ParseSettingsLine(line)
    ElseIf Left(line, 5) = "Grbl "
      AddLog("GRBL banner: " + line, "INFO")
      DrawPortStatus(#True, #True)
      SetGadgetText(#Text_StatusBar, "Connected — " + line)
    ElseIf Left(line, 6) = "[PRB:"
      ; Probe result
      LockMutex(Mutex)
      AddElement(ProbeResults())
      ProbeResults() = line
      UnlockMutex(Mutex)
      If IsGadget(#Editor_ProbeResult)
        AddGadgetItem(#Editor_ProbeResult, -1, line)
      EndIf
      AddLog("Probe result: " + line, "INFO")
    ElseIf Left(line, 6) = "ALARM:"
      AddLog("ALARM: " + line, "ERROR")
      SetGadgetText(#Text_StatusBar, "!! ALARM: " + line)
    ElseIf Left(line, 6) = "error:"
      AddLog("Error: " + line, "ERROR")
    EndIf
  Next
EndProcedure


Procedure SerialThread(Param.i)
  Protected *buf = AllocateMemory(16384)   ; larger buffer
  Protected incoming.s = ""
  Protected avail.i, rd.i, pos.i, line.s, cmd.s
  
  Delay(400)
  SendRealtime(#GRBL_SOFT_RESET)
  Delay(300)
  WriteSerialPortString(SerialPort, "$" + #CRLF$)
  
  While Running And Not ShutdownSignal
    ; Send pending commands
    LockMutex(Mutex)
    While ListSize(PendingCommands()) > 0
      If SerialPort = -1 : Break : EndIf
      FirstElement(PendingCommands())
      cmd = PendingCommands() + #CRLF$
      DeleteElement(PendingCommands())
      UnlockMutex(Mutex)
      WriteSerialPortString(SerialPort, cmd)
      LockMutex(Mutex)
    Wend
    UnlockMutex(Mutex)
    
    ; Read incoming
    If SerialPort <> -1
      avail = AvailableSerialPortInput(SerialPort)
      If avail > 0
        If avail > 16384 : avail = 16384 : EndIf
        rd = ReadSerialPortData(SerialPort, *buf, avail)
        If rd > 0
          incoming + PeekS(*buf, rd, #PB_Ascii)
          While FindString(incoming, #CRLF$)
            pos  = FindString(incoming, #CRLF$)
            line = Left(incoming, pos - 1)
            incoming = Mid(incoming, pos + 2)
            If Trim(line) = "" : Continue : EndIf
            LockMutex(RawMutex)
            AddElement(RawDataQueue()) : RawDataQueue() = line
            UnlockMutex(RawMutex)
          Wend
        EndIf
      EndIf
    EndIf
    Delay(5)
  Wend
  FreeMemory(*buf)
  AddLog("Serial thread exited", "INFO")
EndProcedure

; ConnectToPort, DisconnectPort, ConnectToggleHandler remain the same (except larger buffers in OpenSerialPort)

Procedure ConnectToPort(port.s)
  SerialPort = OpenSerialPort(#PB_Any, port, 115200,
                              #PB_SerialPort_NoParity, 8, 1,
                              #PB_SerialPort_NoHandshake, 1024, 1024)  ; larger buffers
  If SerialPort = 0
    SerialPort = -1
    AddLog("Failed to open " + port, "ERROR")
    MessageRequester("Error", "Cannot open " + port, #PB_MessageRequester_Error)
    DrawPortStatus(#False, #False)
    ProcedureReturn
  EndIf
  Running = #True : ShutdownSignal = #False
  SerialThreadID = CreateThread(@SerialThread(), 0)
  SetGadgetText(#Button_ConnectToggle, "Disconnect")
  DisableGadget(#Combo_Port, #True)
  DisableGadget(#Button_RefreshPorts, #True)
  DrawPortStatus(#True, #False)
  SetGadgetText(#Text_StatusBar, "Connecting to " + port + "...")
  AddLog("Connected to " + port, "INFO")
EndProcedure

Procedure DisconnectPort()
  ShutdownSignal = #True
  GCodeStop = #True
  If IsThread(SerialThreadID)
    WaitThread(SerialThreadID, 1000)
    If IsThread(SerialThreadID) : KillThread(SerialThreadID) : EndIf
  EndIf
  If SerialPort <> -1 : CloseSerialPort(SerialPort) : EndIf
  SerialPort = -1 : Running = #False
  SetGadgetText(#Button_ConnectToggle, "Connect")
  DisableGadget(#Combo_Port, #False)
  DisableGadget(#Button_RefreshPorts, #False)
  DrawPortStatus(#False, #False)
  SetGadgetText(#Text_StatusBar, "Disconnected")
  AddLog("Disconnected", "INFO")
EndProcedure

Procedure ConnectToggleHandler()
  If SerialPort = -1
    Protected port.s = GetGadgetText(#Combo_Port)
    If port = ""
      MessageRequester("Error", "Select a COM port first.", #PB_MessageRequester_Error)
      ProcedureReturn
    EndIf
    If FindString(port,"[")
      port=StringField(port,1," ")
    EndIf
    
    ConnectToPort(port)
    
  Else
    DisconnectPort()
  EndIf
EndProcedure

; ============================================
;   JOG, SETTINGS, GCODE THREAD, UPDATE PROCEDURES
; ============================================
; SendJog, ReadSettings, WriteSelectedSetting remain unchanged
Procedure SendJog(axis.s, dist.d, feed.d, unit.s)
  ; unit = "mm" or "inch"
  Protected unitFlag.s = ""
  If unit = "inch" : unitFlag = "G20" : Else : unitFlag = "G21" : EndIf
  Protected cmd.s = "$J=" + unitFlag + "G91" + axis + StrD(dist, 4) + "F" + StrD(feed, 1)
  SendCommand(cmd)
EndProcedure

; ============================================
;   READ SETTINGS
; ============================================
Procedure ReadSettings()
  LockMutex(SettingMutex)
  ClearList(SettingsList())
  UnlockMutex(SettingMutex)
  SendCommand("$$")
  AddLog("Requested settings ($$)", "INFO")
EndProcedure

; ============================================
;   WRITE SELECTED SETTING
; ============================================
Procedure WriteSelectedSetting()
  Protected idx.i = GetGadgetState(#List_Settings)
  If idx < 0 : ProcedureReturn : EndIf
  Protected newVal.s = Trim(GetGadgetText(#Edit_SettingVal))
  If newVal = "" : ProcedureReturn : EndIf
  
  LockMutex(SettingMutex)
  If SelectElement(SettingsList(), idx)
    Protected num.i = SettingsList()\number
  EndIf
  UnlockMutex(SettingMutex)
  
  Protected cmd.s = "$" + Str(num) + "=" + newVal
  SendCommand(cmd)
  AddLog("Write setting: " + cmd, "INFO")
  Delay(200)
  ReadSettings()
EndProcedure


; GCodeThread - minor improvement: larger buffer
Procedure GCodeThread(Param.i)
  GCodeRunning = #True
  GCodeStop    = #False
  GCodeSent    = 0
  GCodeAckOk   = 0
  
  Protected *buf     = AllocateMemory(8192)
  Protected incoming.s = ""
  Protected avail.i, rd.i, pos.i, line.s
  Protected grblBuf.i = 0       ; bytes in GRBL serial buffer (RX buffer = 128 bytes)
  Protected MaxBuf.i  = 120     ; safe limit
  
  LockMutex(Mutex)
  Protected total.i = ListSize(GCodeLines())
  Protected NewList localLines.s()
  ForEach GCodeLines() : AddElement(localLines()) : localLines() = GCodeLines() : Next
  UnlockMutex(Mutex)
  
  ResetList(localLines())
  While NextElement(localLines()) And Not GCodeStop And Running
    Protected gcLine.s = Trim(localLines())
    ; Strip comments
    If Left(gcLine, 1) = ";" Or Left(gcLine, 1) = "(" Or gcLine = "" : Continue : EndIf
    Protected sendStr.s = gcLine + #CRLF$
    Protected sendLen.i = Len(sendStr)
    
    ; Wait until there is room in GRBL buffer
    Protected waited.i = 0
    While (grblBuf + sendLen > MaxBuf) And Not GCodeStop
      ; Read any available responses
      If SerialPort <> -1
        avail = AvailableSerialPortInput(SerialPort)
        If avail > 0
          If avail > 4096 : avail = 4096 : EndIf
          rd = ReadSerialPortData(SerialPort, *buf, avail)
          If rd > 0
            incoming + PeekS(*buf, rd, #PB_Ascii)
            While FindString(incoming, #CRLF$)
              pos  = FindString(incoming, #CRLF$)
              line = Left(incoming, pos - 1)
              incoming = Mid(incoming, pos + 2)
              If Left(line, 2) = "ok" Or Left(line, 5) = "error"
                grblBuf - sendLen
                If grblBuf < 0 : grblBuf = 0 : EndIf
                GCodeAckOk + 1
                LockMutex(RawMutex)
                AddElement(RawDataQueue()) : RawDataQueue() = line
                UnlockMutex(RawMutex)
              EndIf
            Wend
          EndIf
        EndIf
      EndIf
      Delay(2)
      waited + 2
      If waited > 10000 : Break : EndIf  ; 10s timeout
    Wend
    
    If GCodeStop Or Not Running : Break : EndIf
    
    ; Send line
    If SerialPort <> -1
      WriteSerialPortString(SerialPort, sendStr)
      grblBuf + sendLen
      GCodeSent + 1
    EndIf
  Wend
  
  ; Drain remaining oks
  Protected drain.i = 0
  While grblBuf > 0 And drain < 5000 And SerialPort <> -1
    avail = AvailableSerialPortInput(SerialPort)
    If avail > 0
      If avail > 4096 : avail = 4096 : EndIf
      rd = ReadSerialPortData(SerialPort, *buf, avail)
      If rd > 0
        incoming + PeekS(*buf, rd, #PB_Ascii)
        While FindString(incoming, #CRLF$)
          pos  = FindString(incoming, #CRLF$)
          line = Left(incoming, pos - 1)
          incoming = Mid(incoming, pos + 2)
          If Left(line, 2) = "ok" Or Left(line, 5) = "error"
            grblBuf - 10 : If grblBuf < 0 : grblBuf = 0 : EndIf
          EndIf
        Wend
      EndIf
    EndIf
    Delay(5) : drain + 5
  Wend
  
  FreeMemory(*buf)
  GCodeRunning = #False
  AddLog("GCode stream finished. Sent=" + Str(GCodeSent) + " Ack=" + Str(GCodeAckOk), "INFO")
EndProcedure


Procedure StartGCodeStream()
  If SerialPort = -1
    MessageRequester("Error", "Not connected.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  If GCodeRunning
    MessageRequester("Error", "GCode already running.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  Protected raw.s = GetGadgetText(#Editor_GCode)
  If Trim(raw) = ""
    MessageRequester("Error", "No GCode loaded.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  LockMutex(Mutex)
  ClearList(GCodeLines())
  Protected i.i
  For i = 1 To CountString(raw, #CRLF$) + 1
    Protected ln.s = StringField(raw, i, #CRLF$)
    If Trim(ln) <> ""
      AddElement(GCodeLines()) : GCodeLines() = ln
    EndIf
  Next
  GCodeTotal = ListSize(GCodeLines())
  UnlockMutex(Mutex)
  GCodeThreadID = CreateThread(@GCodeThread(), 0)
  AddLog("GCode stream started (" + Str(GCodeTotal) + " lines)", "INFO")
EndProcedure

Procedure StopGCodeStream()
  GCodeStop = #True
  SendRealtime(#GRBL_FEED_HOLD)
  AddLog("GCode stream stopped by user", "WARNING")
EndProcedure

; ============================================
;   UPDATE STATUS BAR & POSITION DISPLAY
; ============================================
Procedure UpdateStatusBar()
  LockMutex(StatusMutex)
  Protected state.s = CurrentStatus\state
  Protected mx.d = CurrentStatus\mx, my.d = CurrentStatus\my, mz.d = CurrentStatus\mz
  Protected wx.d = CurrentStatus\wx, wy.d = CurrentStatus\wy, wz.d = CurrentStatus\wz
  Protected feed.d = CurrentStatus\feed, spd.d = CurrentStatus\spindle
  Protected ovf.i = CurrentStatus\ov_feed
  Protected ovr.i = CurrentStatus\ov_rapid
  Protected ovs.i = CurrentStatus\ov_spindle
  Protected flood.i = CurrentStatus\flood
  Protected mist.i  = CurrentStatus\mist
  UnlockMutex(StatusMutex)
  
  If state = "" : ProcedureReturn : EndIf
  
  SetGadgetText(#Text_MachineState, "State: " + state)
  SetGadgetText(#Text_MachinePos,
                "MPos  X:" + StrD(mx,3) + "  Y:" + StrD(my,3) + "  Z:" + StrD(mz,3))
  SetGadgetText(#Text_WorkPos,
                "WPos  X:" + StrD(wx,3) + "  Y:" + StrD(wy,3) + "  Z:" + StrD(wz,3))
  
  Protected bar.s = state + "  F:" + StrD(feed,0) + " S:" + StrD(spd,0)
  If ovf  : bar + "  OvF:"  + Str(ovf)  + "%" : EndIf
  If ovr  : bar + " OvR:"  + Str(ovr)  + "%" : EndIf
  If ovs  : bar + " OvS:"  + Str(ovs)  + "%" : EndIf
  If flood : bar + "  [FLOOD]" : EndIf
  If mist  : bar + " [MIST]"  : EndIf
  SetGadgetText(#Text_StatusBar, bar)
  
  ; Colour state label by machine state
  Protected stateCol.i
  Select state
    Case "Idle"  : stateCol = RGB(0,180,0)
    Case "Run"   : stateCol = RGB(0,120,255)
    Case "Hold:0","Hold:1" : stateCol = RGB(255,165,0)
    Case "Jog"   : stateCol = RGB(0,200,200)
    Case "Alarm" : stateCol = RGB(220,0,0)
    Case "Door:0","Door:1","Door:2","Door:3" : stateCol = RGB(200,0,200)
    Case "Check" : stateCol = RGB(180,180,0)
    Case "Home"  : stateCol = RGB(0,200,100)
    Case "Sleep" : stateCol = RGB(100,100,100)
    Default      : stateCol = RGB(180,180,180)
  EndSelect
  ; We can't set text colour on TextGadget easily without owner-draw,
  ; so embed state in status bar text (already done above)
  
  ; Update overrides tab labels
  If IsGadget(#Text_OvFeedVal)
    SetGadgetText(#Text_OvFeedVal,    "Feed:    " + Str(ovf) + "%")
    SetGadgetText(#Text_OvRapidVal,   "Rapid:   " + Str(ovr) + "%")
    SetGadgetText(#Text_OvSpindleVal, "Spindle: " + Str(ovs) + "%")
  EndIf
  
  ; GCode progress
  If GCodeRunning And IsGadget(#ProgressBar_GCode)
    If GCodeTotal > 0
      SetGadgetState(#ProgressBar_GCode, GCodeSent * 100 / GCodeTotal)
      SetGadgetText(#Text_GCodeStatus,
                    "Streaming: " + Str(GCodeSent) + " / " + Str(GCodeTotal) + " lines")
    EndIf
  ElseIf Not GCodeRunning And IsGadget(#ProgressBar_GCode)
    If GCodeSent > 0 And GCodeSent = GCodeTotal
      SetGadgetText(#Text_GCodeStatus, "Stream complete")
    EndIf
  EndIf
  
  ; Refresh settings list if populated
  If IsGadget(#List_Settings)
    Protected cnt.i = CountGadgetItems(#List_Settings)
    LockMutex(SettingMutex)
    Protected sz.i = ListSize(SettingsList())
    UnlockMutex(SettingMutex)
    If sz > 0 And cnt <> sz
      ClearGadgetItems(#List_Settings)
      LockMutex(SettingMutex)
      ForEach SettingsList()
        AddGadgetItem(#List_Settings, -1,
                      "$" + Str(SettingsList()\number) + " = " + SettingsList()\value +
                      "   (" + SettingsList()\description + ")")
      Next
      UnlockMutex(SettingMutex)
    EndIf
  EndIf
EndProcedure

; ============================================
;   SAFE GUI UPDATE (called from timer)
; ============================================
Procedure SafeUpdateGUI()
  ProcessRawQueue()
  UpdateStatusBar()
  
  ; Auto-update port indicator based on scan results
  LockMutex(ScanMutex)
  Protected grblFound.i = #False
  Protected curPort.s = GetGadgetText(#Combo_Port)
  ForEach GRBLPorts()
    If GRBLPorts() = curPort
      grblFound = #True
      ; Colour the combo item (limited in PureBasic, so we just update indicator)
    EndIf
  Next
  UnlockMutex(ScanMutex)
  
  If SerialPort = -1
    ; Update combo items to show which ports are GRBL
    Protected i.i
    LockMutex(ScanMutex)
    For i = 0 To CountGadgetItems(#Combo_Port) - 1
      Protected itemTxt.s = GetGadgetItemText(#Combo_Port, i, 0)
      Protected cleanPort.s = StringField(itemTxt, 1, " ")
      Protected isGRBL.i = #False
      ForEach GRBLPorts()
        If GRBLPorts() = cleanPort : isGRBL = #True : Break : EndIf
      Next
      If isGRBL And FindString(itemTxt, " [GRBL]") = 0
        SetGadgetItemText(#Combo_Port, i, cleanPort + " [GRBL]", 0)
      EndIf
    Next
    UnlockMutex(ScanMutex)
    DrawPortStatus(#False, #False)
  ElseIf SerialPort <> -1 And grblFound
    DrawPortStatus(#True, #True)
  ElseIf SerialPort <> -1
    DrawPortStatus(#True, #False)
  EndIf
  
  If LogWindowOpen : UpdateLogWindow() : EndIf
EndProcedure


; ============================================
;   TAB BUILDERS & EVENT HANDLERS
; ============================================
; All BuildTabXXX, handler procedures (ConsoleSendHandler, JogXPlusHandler, etc.) remain unchanged
; Only realtime calls now use the corrected constants (already handled by the new #GRBL_ definitions)
Procedure BuildTabConsole(x.i, y.i, w.i, h.i)
  Protected bh.i = h - 70
  EditorGadget(#Editor_Console, x+5, y+5, w-10, bh,
               #PB_Editor_ReadOnly)
  StringGadget(#Edit_ConsoleInput, x+5, y+bh+10, w-90, 25, "")
  ButtonGadget(#Button_ConsoleSend,  x+w-80, y+bh+10, 75, 25, "Send")
  ButtonGadget(#Button_ConsoleClear, x+5,    y+bh+40, 90, 22, "Clear")
  CheckBoxGadget(#Check_AutoScroll,  x+110,  y+bh+40, 120, 22, "Auto-scroll")
  SetGadgetState(#Check_AutoScroll, #PB_Checkbox_Checked)
  
  BindGadgetEvent(#Button_ConsoleSend, @ConsoleSendHandler())
  BindGadgetEvent(#Edit_ConsoleInput,  @ConsoleInputHandler())
  BindGadgetEvent(#Button_ConsoleClear,@ConsoleClearHandler())
EndProcedure

Procedure BuildTabJog(x.i, y.i, w.i, h.i)
  Protected cx.i = x + w/2, cy.i = y + 120
  Protected bw.i = 60, bh.i = 30
  
  ; Jog parameters
  TextGadget(#Text_JogStep, x+5, y+5, 60, 20, "Step:")
  SpinGadget(#Spin_JogStep, x+70, y+3, 80, 22, 1, 10000, #PB_Spin_Numeric)
  SetGadgetState(#Spin_JogStep, 10) : SetGadgetText(#Spin_JogStep, "10")
  
  TextGadget(#Text_JogFeed, x+5, y+35, 60, 20, "Feed mm/min:")
  SpinGadget(#Spin_JogFeed, x+70, y+33, 80, 22, 1, 10000, #PB_Spin_Numeric)
  SetGadgetState(#Spin_JogFeed, 500) : SetGadgetText(#Spin_JogFeed, "500")
  
  ComboBoxGadget(#Combo_JogUnit, x+165, y+3, 60, 22)
  AddGadgetItem(#Combo_JogUnit, -1, "mm")
  AddGadgetItem(#Combo_JogUnit, -1, "inch")
  SetGadgetState(#Combo_JogUnit, 0)
  
  ; XY jog pad
  ButtonGadget(#Button_JogYPlus,  cx-bw/2, cy-bh-15,  bw, bh, "Y+")
  ButtonGadget(#Button_JogXMinus, cx-bw-30,cy-bh/2,  bw, bh, "X-")
  ButtonGadget(#Button_JogXPlus,  cx+30,   cy-bh/2,  bw, bh, "X+")
  ButtonGadget(#Button_JogYMinus, cx-bw/2, cy+15,     bw, bh, "Y-")
  ButtonGadget(#Button_JogStop,   cx-bw/2, cy-bh/2,  bw, bh, "STOP")
  
  ; Z axis
  ButtonGadget(#Button_JogZPlus,  cx+120, cy-bh-5, bw, bh, "Z+")
  ButtonGadget(#Button_JogZMinus, cx+120, cy+5,    bw, bh, "Z-")
  
  ; Homing
  Protected hy.i = cy + 70
  ButtonGadget(#Button_HomeAll,  x+5,   hy,    80, 28, "Home All")
  ButtonGadget(#Button_HomeX,    x+95,  hy,    55, 28, "Home X")
  ButtonGadget(#Button_HomeY,    x+160, hy,    55, 28, "Home Y")
  ButtonGadget(#Button_HomeZ,    x+225, hy,    55, 28, "Home Z")
  
  ; Zero WCS
  Protected zy.i = hy + 38
  ButtonGadget(#Button_ZeroAll,  x+5,   zy,    80, 28, "Zero All")
  ButtonGadget(#Button_ZeroX,    x+95,  zy,    55, 28, "Zero X")
  ButtonGadget(#Button_ZeroY,    x+160, zy,    55, 28, "Zero Y")
  ButtonGadget(#Button_ZeroZ,    x+225, zy,    55, 28, "Zero Z")
  ButtonGadget(#Button_GoToZero, x+290, zy,    80, 28, "Go to Zero")
  
  ; Control buttons
  Protected cby.i = zy + 48
  ButtonGadget(#Button_SoftReset,   x+5,   cby, 90, 30, "Soft Reset")
  ButtonGadget(#Button_FeedHold,    x+105, cby, 90, 30, "Feed Hold")
  ButtonGadget(#Button_CycleStart,  x+205, cby, 90, 30, "Cycle Start")
  ButtonGadget(#Button_UnlockAlarm, x+305, cby, 90, 30, "Unlock ($X)")
  
  ; Bind jog buttons
  BindGadgetEvent(#Button_JogXPlus,  @JogXPlusHandler())
  BindGadgetEvent(#Button_JogXMinus, @JogXMinusHandler())
  BindGadgetEvent(#Button_JogYPlus,  @JogYPlusHandler())
  BindGadgetEvent(#Button_JogYMinus, @JogYMinusHandler())
  BindGadgetEvent(#Button_JogZPlus,  @JogZPlusHandler())
  BindGadgetEvent(#Button_JogZMinus, @JogZMinusHandler())
  BindGadgetEvent(#Button_JogStop,   @JogStopHandler())
  BindGadgetEvent(#Button_HomeAll,   @HomeAllHandler())
  BindGadgetEvent(#Button_HomeX,     @HomeXHandler())
  BindGadgetEvent(#Button_HomeY,     @HomeYHandler())
  BindGadgetEvent(#Button_HomeZ,     @HomeZHandler())
  BindGadgetEvent(#Button_ZeroAll,   @ZeroAllHandler())
  BindGadgetEvent(#Button_ZeroX,     @ZeroXHandler())
  BindGadgetEvent(#Button_ZeroY,     @ZeroYHandler())
  BindGadgetEvent(#Button_ZeroZ,     @ZeroZHandler())
  BindGadgetEvent(#Button_GoToZero,  @GoToZeroHandler())
  BindGadgetEvent(#Button_SoftReset,   @SoftResetHandler())
  BindGadgetEvent(#Button_FeedHold,    @FeedHoldHandler())
  BindGadgetEvent(#Button_CycleStart,  @CycleStartHandler())
  BindGadgetEvent(#Button_UnlockAlarm, @UnlockAlarmHandler())
EndProcedure

Procedure BuildTabSettings(x.i, y.i, w.i, h.i)
  ButtonGadget(#Button_SettingsRead, x+5, y+5, 100, 25, "Read ($$)")
  ButtonGadget(#Button_SettingsSaveFile, x+115, y+5, 110, 25, "Save to file")
  ButtonGadget(#Button_SettingsLoadFile, x+235, y+5, 110, 25, "Load from file")
  
  ListViewGadget(#List_Settings, x+5, y+38, w-10, h-110)
  
  TextGadget(#Text_SettingVal, x+5, y+h-65, 60, 20, "New value:")
  StringGadget(#Edit_SettingVal, x+70, y+h-67, 120, 22, "")
  ButtonGadget(#Button_SettingWrite, x+200, y+h-67, 100, 25, "Write ($x=val)")
  
  BindGadgetEvent(#Button_SettingsRead,    @SettingsReadHandler())
  BindGadgetEvent(#Button_SettingWrite,    @SettingWriteHandler())
  BindGadgetEvent(#Button_SettingsSaveFile,@SettingsSaveHandler())
  BindGadgetEvent(#Button_SettingsLoadFile,@SettingsLoadHandler())
  BindGadgetEvent(#List_Settings,          @SettingsListClickHandler())
EndProcedure

Procedure BuildTabProbing(x.i, y.i, w.i, h.i)
  Protected lx.i = x+5, rx.i = x+200
  
  TextGadget(#Text_ProbeSeek,  lx, y+5,  120, 20, "Seek feed (mm/min):")
  SpinGadget(#Spin_ProbeSeek,  lx+130, y+3, 80, 22, 1, 5000, #PB_Spin_Numeric)
  SetGadgetState(#Spin_ProbeSeek, 200) : SetGadgetText(#Spin_ProbeSeek, "200")
  
  TextGadget(#Text_ProbeFeed,  lx, y+35, 120, 20, "Probe feed (mm/min):")
  SpinGadget(#Spin_ProbeFeed,  lx+130, y+33, 80, 22, 1, 1000, #PB_Spin_Numeric)
  SetGadgetState(#Spin_ProbeFeed, 50) : SetGadgetText(#Spin_ProbeFeed, "50")
  
  TextGadget(#Text_ProbeDepth, lx, y+65, 120, 20, "Max depth (mm):")
  SpinGadget(#Spin_ProbeDepth, lx+130, y+63, 80, 22, 1, 100, #PB_Spin_Numeric)
  SetGadgetState(#Spin_ProbeDepth, 20) : SetGadgetText(#Spin_ProbeDepth, "20")
  
  TextGadget(#Text_ProbePlate, lx, y+95, 120, 20, "Plate thickness (mm):")
  SpinGadget(#Spin_ProbePlateThick, lx+130, y+93, 80, 22, 0, 50, #PB_Spin_Numeric)
  SetGadgetState(#Spin_ProbePlateThick, 0) : SetGadgetText(#Spin_ProbePlateThick, "0")
  
  CheckBoxGadget(#Check_ProbeAutoZero, lx, y+125, 200, 22, "Auto zero Z after probe")
  SetGadgetState(#Check_ProbeAutoZero, #PB_Checkbox_Checked)
  
  ButtonGadget(#Button_ProbeZ,   lx,    y+155, 120, 30, "Probe Z")
  ButtonGadget(#Button_ProbeXY,  lx+130,y+155, 120, 30, "Probe XY (G38.2)")
  ButtonGadget(#Button_ProbeClear, lx,  y+195, 100, 25, "Clear results")
  
  EditorGadget(#Editor_ProbeResult, lx, y+230, w-10, h-240, #PB_Editor_ReadOnly)
  
  BindGadgetEvent(#Button_ProbeZ,     @ProbeZHandler())
  BindGadgetEvent(#Button_ProbeXY,    @ProbeXYHandler())
  BindGadgetEvent(#Button_ProbeClear, @ProbeClearHandler())
EndProcedure

Procedure BuildTabOverrides(x.i, y.i, w.i, h.i)
  Protected col1.i = x+5, col2.i = x+220, col3.i = x+440
  
  ; Feed override
  FrameGadget(#PB_Any, col1, y+5, 200, 180, "Feed Override")
  TextGadget(#Text_OvFeedVal, col1+10, y+25, 170, 20, "Feed: 100%")
  ButtonGadget(#Button_OvFeedPlus10,  col1+10, y+50, 80, 28, "+10%")
  ButtonGadget(#Button_OvFeedMinus10, col1+100,y+50, 80, 28, "-10%")
  ButtonGadget(#Button_OvFeedPlus1,   col1+10, y+85, 80, 28, "+1%")
  ButtonGadget(#Button_OvFeedMinus1,  col1+100,y+85, 80, 28, "-1%")
  ButtonGadget(#Button_OvFeedReset,   col1+10, y+120,170, 28, "Reset 100%")
  
  ; Rapid override
  FrameGadget(#PB_Any, col2, y+5, 200, 180, "Rapid Override")
  TextGadget(#Text_OvRapidVal, col2+10, y+25, 170, 20, "Rapid: 100%")
  ButtonGadget(#Button_OvRapidHigh, col2+10, y+50,  170, 28, "100% (High)")
  ButtonGadget(#Button_OvRapidMed,  col2+10, y+85,  170, 28, "50% (Medium)")
  ButtonGadget(#Button_OvRapidLow,  col2+10, y+120, 170, 28, "25% (Low)")
  
  ; Spindle override
  FrameGadget(#PB_Any, col3, y+5, 200, 180, "Spindle Override")
  TextGadget(#Text_OvSpindleVal, col3+10, y+25, 170, 20, "Spindle: 100%")
  ButtonGadget(#Button_OvSpindlePlus10,  col3+10, y+50,  80, 28, "+10%")
  ButtonGadget(#Button_OvSpindleMinus10, col3+100,y+50,  80, 28, "-10%")
  ButtonGadget(#Button_OvSpindlePlus1,   col3+10, y+85,  80, 28, "+1%")
  ButtonGadget(#Button_OvSpindleMinus1,  col3+100,y+85,  80, 28, "-1%")
  ButtonGadget(#Button_OvSpindleReset,   col3+10, y+120, 170, 28, "Reset 100%")
  
  ; Coolant
  Protected cy2.i = y + 200
  FrameGadget(#PB_Any, col1, cy2, 200, 80, "Coolant")
  ButtonGadget(#Button_OvFloodToggle, col1+10, cy2+25, 80, 30, "Flood Toggle")
  ButtonGadget(#Button_OvMistToggle,  col1+100,cy2+25, 80, 30, "Mist Toggle")
  
  ; Bind
  BindGadgetEvent(#Button_OvFeedPlus10,  @OvFeedP10())
  BindGadgetEvent(#Button_OvFeedMinus10, @OvFeedM10())
  BindGadgetEvent(#Button_OvFeedPlus1,   @OvFeedP1())
  BindGadgetEvent(#Button_OvFeedMinus1,  @OvFeedM1())
  BindGadgetEvent(#Button_OvFeedReset,   @OvFeedReset())
  BindGadgetEvent(#Button_OvRapidHigh,   @OvRapidHigh())
  BindGadgetEvent(#Button_OvRapidMed,    @OvRapidMed())
  BindGadgetEvent(#Button_OvRapidLow,    @OvRapidLow())
  BindGadgetEvent(#Button_OvSpindlePlus10,  @OvSpindleP10())
  BindGadgetEvent(#Button_OvSpindleMinus10, @OvSpindleM10())
  BindGadgetEvent(#Button_OvSpindlePlus1,   @OvSpindleP1())
  BindGadgetEvent(#Button_OvSpindleMinus1,  @OvSpindleM1())
  BindGadgetEvent(#Button_OvSpindleReset, @OvSpindleReset())
  BindGadgetEvent(#Button_OvFloodToggle,  @OvFloodToggle())
  BindGadgetEvent(#Button_OvMistToggle,   @OvMistToggle())
EndProcedure

Procedure BuildTabInfo(x.i, y.i, w.i, h.i)
  Protected bw.i = 150, bh.i = 28, bx.i = x+5, by.i = y+5
  
  ButtonGadget(#Button_GetBuildInfo,     bx,       by,    bw, bh, "Build Info ($I)")
  ButtonGadget(#Button_GetStartup,       bx+bw+5,  by,    bw, bh, "Startup ($N)")
  ButtonGadget(#Button_GetParserState,   bx,       by+38, bw, bh, "Parser State ($G)")
  ButtonGadget(#Button_ViewParams,       bx+bw+5,  by+38, bw, bh, "View Params ($#)")
  ButtonGadget(#Button_ViewBuildOptions, bx,       by+76, bw, bh, "Build Options ($B)")
  ButtonGadget(#Button_GetCheckMode,     bx+bw+5,  by+76, bw, bh, "Check Mode ($C)")
  
  EditorGadget(#Editor_EEPROMInfo, x+5, y+120, w-10, h-130, #PB_Editor_ReadOnly)
  
  BindGadgetEvent(#Button_GetBuildInfo,     @GetBuildInfoHandler())
  BindGadgetEvent(#Button_GetStartup,       @GetStartupHandler())
  BindGadgetEvent(#Button_GetParserState,   @GetParserStateHandler())
  BindGadgetEvent(#Button_ViewParams,       @ViewParamsHandler())
  BindGadgetEvent(#Button_ViewBuildOptions, @ViewBuildOptionsHandler())
  BindGadgetEvent(#Button_GetCheckMode,     @GetCheckModeHandler())
EndProcedure

Procedure BuildTabGCode(x.i, y.i, w.i, h.i)
  ButtonGadget(#Button_GCodeOpen,  x+5,   y+5,  100, 28, "Open File")
  ButtonGadget(#Button_GCodeSend,  x+115, y+5,  100, 28, "Start Stream")
  ButtonGadget(#Button_GCodeStop,  x+225, y+5,  100, 28, "Stop")
  ButtonGadget(#Button_GCodeClear, x+335, y+5,  100, 28, "Clear")
  CheckBoxGadget(#Check_GCodeDryRun, x+445, y+8, 120, 22, "Dry run ($C)")
  
  ProgressBarGadget(#ProgressBar_GCode, x+5, y+40, w-10, 18, 0, 100)
  TextGadget(#Text_GCodeStatus, x+5, y+62, w-10, 20, "No file loaded")
  
  EditorGadget(#Editor_GCode, x+5, y+88, w-10, h-100)
  
  BindGadgetEvent(#Button_GCodeOpen,  @GCodeOpenHandler())
  BindGadgetEvent(#Button_GCodeSend,  @GCodeSendHandler())
  BindGadgetEvent(#Button_GCodeStop,  @GCodeStopHandler())
  BindGadgetEvent(#Button_GCodeClear, @GCodeClearHandler())
EndProcedure

; ============================================
;   RESIZE
; ============================================
Procedure ResizeMainWindow()
  Protected ww.i = WindowWidth(#Window_Main)
  Protected wh.i = WindowHeight(#Window_Main)
  If ww < 900 : ww = 900 : EndIf
  If wh < 600 : wh = 600 : EndIf
  
  ResizeGadget(#Tab_Main,       0,   90, ww,   wh-130)
  ResizeGadget(#Text_StatusBar, 0,   wh-38, ww-2, 20)
  ResizeGadget(#Text_MachinePos,200, 5,    350,  20)
  ResizeGadget(#Text_WorkPos,   200, 27,   350,  20)
  ResizeGadget(#Text_MachineState, 560, 5, 200,  20)
  ResizeGadget(#Button_ShowLog, ww-140, wh-30, 130, 25)
  ResizeGadget(#Button_SaveLog, ww-280, wh-30, 130, 25)
EndProcedure

; ============================================
;   EVENT HANDLER PROCEDURES
; ============================================

; --- Console ---
Procedure ConsoleSendHandler()
  Protected cmd.s = Trim(GetGadgetText(#Edit_ConsoleInput))
  If cmd = "" : ProcedureReturn : EndIf
  AppendConsole("> " + cmd)
  SendCommand(cmd)
  SetGadgetText(#Edit_ConsoleInput, "")
EndProcedure

Procedure ConsoleInputHandler()
  If EventType() =#PB_EventType_LeftClick; #PB_EventType_ReturnKey
    ConsoleSendHandler()
  EndIf
EndProcedure

Procedure ConsoleClearHandler()
  ClearGadgetItems(#Editor_Console)
EndProcedure

; --- Jog ---
Procedure JogXPlusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("X", Step1, feed, unit)
EndProcedure
Procedure JogXMinusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("X", -Step1, feed, unit)
EndProcedure
Procedure JogYPlusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("Y", Step1, feed, unit)
EndProcedure
Procedure JogYMinusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("Y", -Step1, feed, unit)
EndProcedure
Procedure JogZPlusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("Z", Step1, feed, unit)
EndProcedure
Procedure JogZMinusHandler()
  Protected Step1.d = GetGadgetState(#Spin_JogStep)
  Protected feed.d = GetGadgetState(#Spin_JogFeed)
  Protected unit.s = GetGadgetItemText(#Combo_JogUnit, GetGadgetState(#Combo_JogUnit))
  SendJog("Z", -Step1, feed, unit)
EndProcedure
Procedure JogStopHandler()
  SendRealtime(#GRBL_JOG_CANCEL)
EndProcedure

; --- Homing ---
Procedure HomeAllHandler()  : SendCommand("$H")  : EndProcedure
Procedure HomeXHandler()    : SendCommand("$HX") : EndProcedure
Procedure HomeYHandler()    : SendCommand("$HY") : EndProcedure
Procedure HomeZHandler()    : SendCommand("$HZ") : EndProcedure

; --- Zero WCS ---
Procedure ZeroAllHandler()
  SendCommand("G10 L20 P1 X0 Y0 Z0")
EndProcedure
Procedure ZeroXHandler()  : SendCommand("G10 L20 P1 X0") : EndProcedure
Procedure ZeroYHandler()  : SendCommand("G10 L20 P1 Y0") : EndProcedure
Procedure ZeroZHandler()  : SendCommand("G10 L20 P1 Z0") : EndProcedure
Procedure GoToZeroHandler()
  SendCommand("G90 G0 X0 Y0")
  SendCommand("G0 Z0")
EndProcedure

; --- Control ---
Procedure SoftResetHandler()
  SendRealtime(#GRBL_SOFT_RESET)
  AddLog("Soft reset sent", "WARNING")
EndProcedure
Procedure FeedHoldHandler()   : SendRealtime(#GRBL_FEED_HOLD)  : EndProcedure
Procedure CycleStartHandler() : SendRealtime(#GRBL_CYCLE_START): EndProcedure
Procedure UnlockAlarmHandler(): SendCommand("$X")              : EndProcedure

; --- Settings ---
Procedure SettingsReadHandler()  : ReadSettings()          : EndProcedure
Procedure SettingWriteHandler()  : WriteSelectedSetting()  : EndProcedure

Procedure SettingsListClickHandler()
  Protected idx.i = GetGadgetState(#List_Settings)
  If idx < 0 : ProcedureReturn : EndIf
  LockMutex(SettingMutex)
  If SelectElement(SettingsList(), idx)
    SetGadgetText(#Edit_SettingVal, SettingsList()\value)
  EndIf
  UnlockMutex(SettingMutex)
EndProcedure

Procedure SettingsSaveHandler()
  Protected fn.s = SaveFileRequester("Save Settings", "grbl_settings.txt", "Text|*.txt",0)
  If fn = "" : ProcedureReturn : EndIf
  Protected f.i = OpenFile(#PB_Any, fn)
  If f
    LockMutex(SettingMutex)
    ForEach SettingsList()
      WriteStringN(f, "$" + Str(SettingsList()\number) + "=" + SettingsList()\value)
    Next
    UnlockMutex(SettingMutex)
    CloseFile(f)
    AddLog("Settings saved to " + fn, "INFO")
  EndIf
EndProcedure

Procedure SettingsLoadHandler()
  Protected fn.s = OpenFileRequester("Load Settings", "", "Text|*.txt",0)
  If fn = "" : ProcedureReturn : EndIf
  Protected f.i = ReadFile(#PB_Any, fn)
  If f
    While Not Eof(f)
      Protected ln.s = ReadString(f)
      If Left(ln,1) = "$" And FindString(ln,"=")
        SendCommand(ln)
        Delay(50)
      EndIf
    Wend
    CloseFile(f)
    AddLog("Settings loaded from " + fn + " and sent", "INFO")
    Delay(500)
    ReadSettings()
  EndIf
EndProcedure

; --- Probing ---
Procedure ProbeZHandler()
  Protected seek.i  = GetGadgetState(#Spin_ProbeSeek)
  Protected feed.i  = GetGadgetState(#Spin_ProbeFeed)
  Protected depth.i = GetGadgetState(#Spin_ProbeDepth)
  Protected plate.d = GetGadgetState(#Spin_ProbePlateThick)
  Protected autoZ.i = GetGadgetState(#Check_ProbeAutoZero)
  
  ; G38.2 probe toward workpiece
  Protected cmd.s = "G38.2 Z-" + Str(depth) + " F" + Str(feed)
  SendCommand(cmd)
  AddLog("Probe Z sent: " + cmd, "INFO")
  
  If autoZ = #PB_Checkbox_Checked
    ; After probe, set Z to plate thickness
    SendCommand("G10 L20 P1 Z" + StrD(plate, 3))
    AddLog("Auto zero Z to plate thickness " + StrD(plate,3) + " mm", "INFO")
  EndIf
EndProcedure

Procedure ProbeXYHandler()
  Protected feed.i  = GetGadgetState(#Spin_ProbeFeed)
  Protected depth.i = GetGadgetState(#Spin_ProbeDepth)
  Protected cmd.s = "G38.2 Z-" + Str(depth) + " F" + Str(feed)
  SendCommand(cmd)
  AddLog("Probe XY (G38.2) sent", "INFO")
EndProcedure

Procedure ProbeClearHandler()
  ClearGadgetItems(#Editor_ProbeResult)
  LockMutex(Mutex)
  ClearList(ProbeResults())
  UnlockMutex(Mutex)
EndProcedure

; --- Overrides ---
Procedure OvFeedP10()   : SendRealtime(#GRBL_OV_FEED_P10)      : EndProcedure
Procedure OvFeedM10()   : SendRealtime(#GRBL_OV_FEED_M10)      : EndProcedure
Procedure OvFeedP1()    : SendRealtime(#GRBL_OV_FEED_P1)       : EndProcedure
Procedure OvFeedM1()    : SendRealtime(#GRBL_OV_FEED_M1)       : EndProcedure
Procedure OvFeedReset() : SendRealtime(#GRBL_OV_FEED_RESET)    : EndProcedure
Procedure OvRapidHigh() : SendRealtime(#GRBL_OV_RAPID_HIGH)    : EndProcedure
Procedure OvRapidMed()  : SendRealtime(#GRBL_OV_RAPID_MED)     : EndProcedure
Procedure OvRapidLow()  : SendRealtime(#GRBL_OV_RAPID_LOW)     : EndProcedure
Procedure OvSpindleP10(): SendRealtime(#GRBL_OV_SPINDLE_P10)   : EndProcedure
Procedure OvSpindleM10(): SendRealtime(#GRBL_OV_SPINDLE_M10)   : EndProcedure
Procedure OvSpindleP1() : SendRealtime(#GRBL_OV_SPINDLE_P1)    : EndProcedure
Procedure OvSpindleM1() : SendRealtime(#GRBL_OV_SPINDLE_M1)    : EndProcedure
Procedure OvSpindleReset():SendRealtime(#GRBL_OV_SPINDLE_RESET): EndProcedure
Procedure OvFloodToggle(): SendRealtime(#GRBL_TOGGLE_FLOOD)    : EndProcedure
Procedure OvMistToggle():  SendRealtime(#GRBL_TOGGLE_MIST)     : EndProcedure

; --- Info tab ---
Procedure GetBuildInfoHandler()
  SendCommand("$I")
  AddLog("Requested build info ($I)", "INFO")
EndProcedure
Procedure GetStartupHandler()
  SendCommand("$N")
  AddLog("Requested startup blocks ($N)", "INFO")
EndProcedure
Procedure GetParserStateHandler()
  SendCommand("$G")
  AddLog("Requested parser state ($G)", "INFO")
EndProcedure
Procedure ViewParamsHandler()
  SendCommand("$#")
  AddLog("Requested parameters ($#)", "INFO")
EndProcedure
Procedure ViewBuildOptionsHandler()
  SendCommand("$B")
  AddLog("Requested build options ($B)", "INFO")
EndProcedure
Procedure GetCheckModeHandler()
  SendCommand("$C")
  CheckModeActive = Bool(Not CheckModeActive)
  AddLog("Check mode toggled ($C) — now " + Bool(CheckModeActive), "INFO")
EndProcedure

; --- GCode ---
Procedure GCodeOpenHandler()
  Protected fn.s = OpenFileRequester("Open GCode", "", "GCode|*.nc;*.gcode;*.tap;*.txt|All|*.*",0)
  If fn = "" : ProcedureReturn : EndIf
  Protected f.i = ReadFile(#PB_Any, fn)
  If f
    Protected txt.s = ""
    While Not Eof(f)
      txt + ReadString(f) + #CRLF$
    Wend
    CloseFile(f)
    SetGadgetText(#Editor_GCode, txt)
    SetGadgetText(#Text_GCodeStatus, "Loaded: " + GetFilePart(fn))
    AddLog("GCode loaded: " + fn, "INFO")
  EndIf
EndProcedure

Procedure GCodeSendHandler()
  If GetGadgetState(#Check_GCodeDryRun) = #PB_Checkbox_Checked
    SendCommand("$C")
    Delay(200)
  EndIf
  StartGCodeStream()
EndProcedure

Procedure GCodeStopHandler()  : StopGCodeStream()                   : EndProcedure
Procedure GCodeClearHandler()
  SetGadgetText(#Editor_GCode, "")
  SetGadgetText(#Text_GCodeStatus, "Cleared")
  SetGadgetState(#ProgressBar_GCode, 0)
EndProcedure


; ============================================
;-   MAIN WINDOW & EVENT LOOP
; ============================================
If OpenWindow(#Window_Main, 0, 0, 1000, 720, #APP_TITLE,
              #PB_Window_SystemMenu | #PB_Window_ScreenCentered |
              #PB_Window_SizeGadget | #PB_Window_MaximizeGadget)
  
  InitSettingDescriptions()
  ; --- Menu ---
  If CreateMenu(#Menu_Main, WindowID(#Window_Main))
    MenuTitle("File")
    MenuItem(1, "Save Log")
    MenuBar()
    MenuItem(2, "Exit")
    MenuTitle("Connection")
    MenuItem(3, "Refresh Ports")
    MenuItem(4, "Scan for GRBL")
    MenuTitle("GRBL")
    MenuItem(5, "Soft Reset (Ctrl-X)")
    MenuItem(6, "Feed Hold")
    MenuItem(7, "Cycle Start")
    MenuItem(8, "Unlock Alarm ($X)")
    MenuBar()
    MenuItem(9,  "Read Settings ($$)")
    MenuItem(10, "Get Status (?)")
  EndIf
  
  ; --- Port panel (top bar) ---
  FrameGadget(#PB_Any, 0, 0, 195, 85, "Serial Port")
  ComboBoxGadget(#Combo_Port, 5, 18, 110, 22)
  ButtonGadget(#Button_RefreshPorts,   5,  46, 80, 24, "Refresh")
  ButtonGadget(#Button_ConnectToggle, 90,  46, 95, 24, "Connect")
  CanvasGadget(#Canvas_PortStatus,   160,  18, 22, 22)
  DrawPortStatus(#False, #False)
  
  ; --- Position display ---
  TextGadget(#Text_MachinePos,   200, 5,  350, 20, "MPos  X:0.000  Y:0.000  Z:0.000")
  TextGadget(#Text_WorkPos,      200, 27, 350, 20, "WPos  X:0.000  Y:0.000  Z:0.000")
  TextGadget(#Text_MachineState, 560, 5,  200, 20, "State: ---")
  
  ; --- Tabs ---
  Define tabH.i = 700 - 130
  ; Build each tab content (coordinates relative to tab content area)
  Define tx.i = 5, ty.i = 25, tw.i = 985, th.i = tabH - 35
  PanelGadget(#Tab_Main, 0, 90, 1000, tabH)
  AddGadgetItem(#Tab_Main, 0, "Console")
  SetGadgetState(#Tab_Main, 0):BuildTabConsole(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 1, "Jog / Motion")
  SetGadgetState(#Tab_Main, 0):BuildTabJog(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 2, "Settings")
  SetGadgetState(#Tab_Main, 2) : BuildTabSettings(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 3, "Probing")
  SetGadgetState(#Tab_Main, 3) : BuildTabProbing(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 4, "Overrides")
  SetGadgetState(#Tab_Main, 4) : BuildTabOverrides(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 5, "Info / EEPROM")
  SetGadgetState(#Tab_Main, 5) : BuildTabInfo(tx, ty, tw, th)
  AddGadgetItem(#Tab_Main, 6, "GCode")
  SetGadgetState(#Tab_Main, 6) : BuildTabGCode(tx, ty, tw, th)
  SetGadgetState(#Tab_Main, 0)  ; back to console
  
  ; --- Status bar ---
  TextGadget(#Text_StatusBar, 0, 700-38, 998, 20, "Not connected")
  ButtonGadget(#Button_SaveLog, 720, 700-30, 130, 25, "Save Log")
  ButtonGadget(#Button_ShowLog, 860, 700-30, 130, 25, "Show Log")
  
  ; --- Bind port / menu events ---
  BindGadgetEvent(#Button_RefreshPorts,   @RefreshPorts())
  BindGadgetEvent(#Button_ConnectToggle,  @ConnectToggleHandler())
  BindGadgetEvent(#Button_ShowLog,        @ToggleLogWindow())
  BindGadgetEvent(#Button_SaveLog,        @SaveLogFile())
  BindEvent(#PB_Event_SizeWindow,         @ResizeMainWindow(), #Window_Main)
  
  ; Timers
  AddWindowTimer(#Window_Main, #Timer_GUI,    250)
  AddWindowTimer(#Window_Main, #Timer_Status, 200)
  
  RefreshPorts()
  ResizeMainWindow()
  AddLog("GRBL Controller started (realtime commands corrected)", "INFO")  
  ; Event loop (unchanged)
  Define event.i, eWin.i, eMenu.i
  Repeat
    event = WaitWindowEvent(50)
    eWin  = EventWindow()
    
    Select event
      Case #PB_Event_CloseWindow
        If eWin = #Window_Main : quit = #True
          ElseIf eWin = #Window_Log : HideLogHandler() : EndIf
        
      Case #PB_Event_Timer
        Select EventTimer()
          Case #Timer_GUI   : SafeUpdateGUI()
          Case #Timer_Status
            If SerialPort <> -1 : SendRealtime(#GRBL_STATUS_QUERY) : EndIf
        EndSelect
        
      Case #PB_Event_Menu
        Select EventMenu()
          Case 1  : SaveLogFile()
          Case 2  : quit = #True
          Case 3  : RefreshPorts()
          Case 4  : ScanPortsForGRBL()
          Case 5  : SendRealtime(#GRBL_SOFT_RESET)
          Case 6  : SendRealtime(#GRBL_FEED_HOLD)
          Case 7  : SendRealtime(#GRBL_CYCLE_START)
          Case 8  : SendCommand("$X")
          Case 9  : ReadSettings()
          Case 10 : SendRealtime(#GRBL_STATUS_QUERY)
        EndSelect
    EndSelect
  Until quit
  
  ; Cleanup
  ShutdownSignal = #True
  GCodeStop = #True
  If IsThread(SerialThreadID) : WaitThread(SerialThreadID, 1000) : EndIf
  If IsThread(GCodeThreadID)  : WaitThread(GCodeThreadID, 1000)  : EndIf
  If SerialPort <> -1 : CloseSerialPort(SerialPort) : EndIf
  FreeMutex(Mutex) : FreeMutex(RawMutex) : FreeMutex(LogMutex)
  FreeMutex(StatusMutex) : FreeMutex(SettingMutex) : FreeMutex(ScanMutex)
EndIf
End
