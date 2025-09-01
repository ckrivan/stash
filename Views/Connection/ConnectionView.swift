import SwiftUI
import os.log

struct ConnectionView: View {
  @Binding var serverAddress: String
  @Binding var isConnected: Bool
  @State private var isAttemptingConnection = false
  @State private var showError = false
  @State private var errorMessage = ""

  var body: some View {
    ZStack {
      VStack(spacing: 20) {
        Image(systemName: "server.rack")
          .font(.system(size: 60))
          .foregroundColor(.accentColor)

        Text("Connect to Stash Server")
          .font(.title2)
          .fontWeight(.semibold)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Server Address")
              .foregroundColor(.secondary)
            TextField("192.168.86.100:9999", text: $serverAddress)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
            Text("Example: 192.168.86.100:9999 or localhost:9999")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: 300)
        .padding(.horizontal)

        Button(action: attemptConnection) {
          if isAttemptingConnection {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle())
          } else {
            Text("Connect")
              .frame(minWidth: 200)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(serverAddress.isEmpty || isAttemptingConnection)
        .controlSize(.large)
      }
      .padding()

      VStack {
        Spacer()
        HStack {
          Spacer()
          Text("v1.4")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding()
        }
      }
    }
    .alert("Connection Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func attemptConnection() {
    guard !serverAddress.isEmpty else { return }

    var address = serverAddress
    if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
      address = "http://" + address
    }
    if !address.contains(":9999") && !address.contains(":443") {
      if address.hasSuffix("/") {
        address.removeLast()
      }
      address += ":9999"
    }

    Logger.connection.info("🔄 Attempting connection to: \(address)")

    guard let url = URL(string: address) else {
      Logger.connection.error("❌ Invalid server address: \(address)")
      errorMessage = "Invalid server address"
      showError = true
      return
    }

    isAttemptingConnection = true

    var request = URLRequest(url: url.appendingPathComponent("graphql"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let query = """
      {
          "query": "{ stats { scene_count } }"
      }
      """

    request.httpBody = query.data(using: .utf8)

    Task {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)

        await MainActor.run {
          guard let httpResponse = response as? HTTPURLResponse else {
            Logger.connection.error("❌ Invalid response type")
            errorMessage = "Invalid response type"
            showError = true
            isAttemptingConnection = false
            return
          }

          switch httpResponse.statusCode {
          case 200:
            Logger.connection.info("✅ Successfully connected to server")
            UserDefaults.standard.set(address, forKey: "serverAddress")
            isConnected = true
          case 401:
            Logger.connection.error("🔒 Authentication required")
            errorMessage = "Authentication required"
            showError = true
          case 422:
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]],
              let firstError = errors.first?["message"] as? String {
              Logger.connection.error("❌ GraphQL Error: \(firstError)")
              errorMessage = "GraphQL Error: \(firstError)"
            } else {
              Logger.connection.error("❌ Invalid query format")
              errorMessage = "Invalid query format"
            }
            showError = true
          default:
            Logger.connection.error("❌ Server returned error: \(httpResponse.statusCode)")
            errorMessage = "Server returned error: \(httpResponse.statusCode)"
            showError = true
          }

          isAttemptingConnection = false
        }
      } catch {
        await MainActor.run {
          Logger.connection.error("❌ Connection failed: \(error.localizedDescription)")
          errorMessage = "Connection failed: \(error.localizedDescription)"
          showError = true
          isAttemptingConnection = false
        }
      }
    }
  }
}
