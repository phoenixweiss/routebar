import Foundation
import XCTest

@testable import RouteBarCore

final class HTTPSHeaderParserTests: XCTestCase {
  func testFragmentedHeadersAndBodyAreNotConfused() {
    var parser = HTTPSHeaderParser()
    XCTAssertNil(parser.append(Data("HTTP/1.1 200 OK\r\nContent-Length: 1000000\r".utf8)))
    guard case .success(200) = parser.append(Data("\n\r\nbody must not be interpreted".utf8)) else {
      return XCTFail("Expected headers to complete without waiting for body")
    }
  }

  func testInterimResponsesAreSkippedAcrossFragments() {
    var parser = HTTPSHeaderParser()
    XCTAssertNil(
      parser.append(Data("HTTP/1.1 103 Early Hints\r\nLink: </a>\r\n\r\nHTTP/1.1 20".utf8)))
    guard case .success(204) = parser.append(Data("4 No Content\r\n\r\n".utf8)) else {
      return XCTFail("Expected final status")
    }
  }

  func testMalformedStatusAndHeadersAreRejected() {
    for response in [
      "HTTP/2 200 OK\r\n\r\n", "HTTP/1.1 20 OK\r\n\r\n", "HTTP/1.1 999 Bad\r\n\r\n",
      "HTTP/1.1 200 OK\r\nBad Header: value\r\n\r\n",
      "HTTP/1.1 200 OK\r\nHeader without colon\r\n\r\n",
      "HTTP/1.1 200 OK\r\nHeader: value\nInjected: value\r\n\r\n",
      "HTTP/1.1 200 OK\r\nHeader: \u{00}\r\n\r\n",
    ] {
      var parser = HTTPSHeaderParser()
      guard case .failure = parser.append(Data(response.utf8)) else {
        XCTFail("Expected malformed response rejection")
        continue
      }
    }
  }

  func testHeadersAndInformationalRepliesAreBounded() {
    for response in [
      "HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: 16_384),
      "HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: 16_384) + "\r\n\r\n",
      String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 9),
    ] {
      var parser = HTTPSHeaderParser()
      guard case .failure = parser.append(Data(response.utf8)) else {
        XCTFail("Expected bounded response rejection")
        continue
      }
    }
  }
}
