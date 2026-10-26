import Foundation
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { precondition(value(), "Expected true", file: file, line: line) }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value(), "Expected false", file: file, line: line) }
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) { precondition(value() == nil, "Expected nil", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { let a = try first(); let b = try second(); precondition(a == b, "Expected equal: \(a), \(b)", file: file, line: line) }
    catch { preconditionFailure("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try value(); preconditionFailure("Expected error", file: file, line: line) } catch {}
}
