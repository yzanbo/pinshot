import Carbon.HIToolbox

/// キーの番号（NSEvent.keyCode と比べる）。数字のまま書かず、ここの名前を使う
enum KeyCode {
    static let escape = UInt16(kVK_Escape)
    static let space = UInt16(kVK_Space)
    static let delete = UInt16(kVK_Delete)
    static let forwardDelete = UInt16(kVK_ForwardDelete)
    static let `return` = UInt16(kVK_Return)
    /// テンキーの enter
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    static let leftArrow = UInt16(kVK_LeftArrow)
    static let rightArrow = UInt16(kVK_RightArrow)
    static let downArrow = UInt16(kVK_DownArrow)
    static let upArrow = UInt16(kVK_UpArrow)
}
