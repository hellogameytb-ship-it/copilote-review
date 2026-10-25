import SwiftUI

/// Data-only inline content, hosted by existing protected panels. No alert, menu or popover.
struct StealthConfirmationView: View {
    var compact = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading, spacing:2) {
                Label("Turn Stealth off?",systemImage:"eye").font(.system(size:12,weight:.semibold))
                Text("Panels may be shared. Stealth stays ON until confirmed.")
                    .font(.system(size:compact ? 10 : 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:4)
            Button("Cancel",action:onCancel)
                .background(InlineControlBounds(id:"StealthCancel",action:onCancel))
                .accessibilityIdentifier("StealthCancel")
            Button("Confirm off",action:onConfirm)
                .background(InlineControlBounds(id:"StealthConfirmOff",action:onConfirm))
                .accessibilityIdentifier("StealthConfirmOff")
        }
        .buttonStyle(.plain)
        .onExitCommand(perform:onCancel)
        .padding(.horizontal,compact ? 12 : 0)
        .frame(height:compact ? 40 : nil)
    }
}
