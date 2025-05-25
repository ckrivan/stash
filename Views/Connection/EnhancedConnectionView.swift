import SwiftUI
import os.log
import UIKit

struct EnhancedConnectionView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showAdvancedOptions = false
    @FocusState private var isAddressFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(UIColor.systemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 25) {
                // Logo area
                VStack(spacing: 15) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .symbolEffect(.pulse)
                    
                    Text("Stash")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Connect to your media server")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 50)
                
                // Connection form
                VStack(spacing: 20) {
                    connectionForm
                    
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                showAdvancedOptions.toggle()
                            }
                        }) {
                            Text(showAdvancedOptions ? "Hide Advanced" : "Advanced Options")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    if showAdvancedOptions {
                        advancedOptions
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Button area
                    connectButton
                }
                .frame(maxWidth: 350)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(radius: 5)
                )
                
                Spacer()
                
                // Version number
                Text("v2.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            }
            .padding()
        }
        .alert("Connection Error", isPresented: .init(
            get: { appModel.connectionError != nil },
            set: { if !$0 { appModel.connectionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = appModel.connectionError {
                Text(error)
            }
        }
        .onAppear {
            isAddressFieldFocused = true
        }
    }
    
    // Connection form
    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server Address")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.secondary)
                
                TextField("192.168.1.100:9999", text: $appModel.serverAddress)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isAddressFieldFocused)
                    .onSubmit {
                        appModel.attemptConnection()
                    }
                
                if !appModel.serverAddress.isEmpty {
                    Button(action: { appModel.serverAddress = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(10)
            
            Text("Example: 192.168.1.100:9999 or localhost:9999")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // Advanced options
    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key (Optional)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                TextField("API Key", text: $appModel.apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .font(.system(.body, design: .monospaced))
            }
            
            Divider()
                .padding(.vertical, 5)
            
            Toggle("Remember Connection", isOn: .constant(true))
                .font(.subheadline)
            
            Toggle("Use HTTPS", isOn: .constant(false))
                .font(.subheadline)
            
            Toggle("Skip Certificate Validation", isOn: .constant(false))
                .font(.subheadline)
            
            Button(action: {
                Task {
                    await appModel.api.testConnection { _ in
                        // Handle completion
                    }
                }
            }) {
                Text("Test Connection")
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.2))
                    )
                    .foregroundColor(.blue)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal)
    }
    
    // Connect button
    private var connectButton: some View {
        Button(action: appModel.attemptConnection) {
            HStack {
                if appModel.isAttemptingConnection {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(.white)
                        .frame(width: 20, height: 20)
                    Text("Connecting...")
                } else {
                    Image(systemName: "arrow.right")
                    Text("Connect")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundColor(.white)
            .bold()
            .shadow(radius: 3)
        }
        .disabled(appModel.serverAddress.isEmpty || appModel.isAttemptingConnection)
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

#Preview {
    EnhancedConnectionView()
        .environmentObject(AppModel())
}