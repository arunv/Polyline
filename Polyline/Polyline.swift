// Polyline.swift
//
// Copyright (c) 2015 Raphaël Mor
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import CoreLocation
import MapKit

// MARK: - Public Classes -

/// This class can be used for :
///
/// - Encoding an [CLLocation] or a [CLLocationCoordinate2D] to a polyline String
/// - Decoding a polyline String to an [CLLocation] or a [CLLocationCoordinate2D]
/// - Encoding / Decoding associated levels
///
/// it is aims to produce the same results as google's iOS sdk not as the online
/// tool which is fuzzy when it comes to rounding values
///
/// it is based on google's algorithm that can be found here :
///
/// :see: https://developers.google.com/maps/documentation/utilities/polylinealgorithm

var locationsCache = NSCache<NSString, LocationContainer>()
public struct Polyline {
    
    /// The array of coordinates (nil if polyline cannot be decoded)
    public let coordinates: [CLLocationCoordinate2D]?
    /// The encoded polyline
    public let encodedPolyline: String
    
    /// The array of levels (nil if cannot be decoded, or is not provided)
    public let levels: [UInt32]?
    /// The encoded levels (nil if cannot be encoded, or is not provided)
    public let encodedLevels: String?
    
    public let timestampAndAccuracy: [TimeAndAccuracy]?
    public let encodedTimestampAndAccuracy: String?
    
    
    
    /// The array of location (computed from coordinates)
    public var locations: [CLLocation]? {
        let key = self.encodedPolyline + "_" + (self.encodedTimestampAndAccuracy ?? "") as NSString
        if let cached = locationsCache.object(forKey: key), cached.locations.count > 0 {
            return cached.locations
        }
        if self.coordinates == nil {
            return nil
        }
        
        if timestampAndAccuracy == nil {
            return self.coordinates.map(toLocations)
        }
        assert(coordinates?.count == timestampAndAccuracy?.count, "Incorrect number of timestamps for coordinates")
        var isOrdered = true
        var lastDate : Date?
        var locations = [CLLocation]()
        for (ii, coordinate) in self.coordinates!.enumerated() {
            let tsAndAcc = timestampAndAccuracy![ii]
            locations.append(
                CLLocation(
                    coordinate: coordinate,
                    altitude: 0,
                    horizontalAccuracy: tsAndAcc.1,
                    verticalAccuracy: 0,
                    course: -1,
                    speed: -1,
                    timestamp: tsAndAcc.0
                )
            )
            if lastDate?.isAfterDate(tsAndAcc.0) == true {
                isOrdered = false
            }
            lastDate = tsAndAcc.0
        }
        var final = [CLLocation]()
        if isOrdered {
            final = locations
        } else {
            final = locations.sorted { $0.timestamp.isBeforeDate($1.timestamp) }
        }
        locationsCache.setObject(LocationContainer(locations: final), forKey: key)
        return final
    }

    public init(coordinates: [CLLocationCoordinate2D], levels: [UInt32]? = nil, precision: Double = 1e5) {
        
        self.coordinates = coordinates
        self.levels = levels
        self.timestampAndAccuracy = nil
        
        encodedPolyline = encodeCoordinates(coordinates, precision: precision)
        encodedLevels = levels.map(encodeLevels)
        encodedTimestampAndAccuracy = nil
    }
    
    #if !os(watchOS)
    /// Convert polyline to MKPolyline to use with MapKit (nil if polyline cannot be decoded)
    @available(tvOS 9.2, *)
    public var mkPolyline: MKPolyline? {
        guard let coordinates = self.coordinates else { return nil }
        let mkPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        return mkPolyline
    }
    #endif
    
    // MARK: - Public Methods -
    
    /// This init encodes a `[CLLocation]`
    ///
    /// - parameter locations: The `Array` of `CLLocation` that you want to encode
    /// - parameter levels: The optional array of levels  that you want to encode (default: `nil`)
    /// - parameter precision: The precision used for encoding (default: `1e5`)
    public init(locations: [CLLocation], levels: [UInt32]? = nil, precision: Double = 1e5) {
        
        self.coordinates = locations.map { $0.coordinate }
        self.levels = levels
        self.timestampAndAccuracy = locations.map { return ($0.timestamp, $0.horizontalAccuracy) }
        
        encodedPolyline = encodeCoordinates(coordinates!, precision: precision)
        encodedLevels = levels.map(encodeLevels)
        encodedTimestampAndAccuracy = encodeTimestampAndAccuracy(timestampAndAccuracy: self.timestampAndAccuracy!)
    }
    
    /// This designated initializer decodes a polyline `String`
    ///
    /// :param: encodedPolyline The polyline that you want to decode
    /// :param: encodedLevels The levels that you want to decode (default: nil)
    /// :param: precision The precision used for decoding (default: 1e5)
    public init(encodedPolyline: String, encodedTimestampAndAccuracy: String? = nil, encodedLevels: String? = nil, precision: Double = 1e5) throws {
        
        self.encodedPolyline = encodedPolyline
        self.encodedLevels = encodedLevels
        self.encodedTimestampAndAccuracy = encodedTimestampAndAccuracy
        
        
        coordinates = decodePolyline(encodedPolyline, precision: precision)
        levels = self.encodedLevels.flatMap(decodeLevels)

        if let tsAndAcc = encodedTimestampAndAccuracy {
            timestampAndAccuracy = decodeTimestampAndAccuracy(encodedString: tsAndAcc)
            if timestampAndAccuracy!.count != coordinates?.count {
                // wat where why how
                throw NSError(domain: "Polyline", code: 103, userInfo: [NSLocalizedDescriptionKey: "Incorrect number of timestamps for coordinates"])
            }
        } else {
            timestampAndAccuracy = nil
        }
    }

}

// MARK: - Public Functions -

/// This function encodes an `[CLLocationCoordinate2D]` to a `String`
///
/// - parameter coordinates: The `Array` of `CLLocationCoordinate2D` that you want to encode
/// - parameter precision: The precision used to encode coordinates (default: `1e5`)
///
/// - returns: A `String` representing the encoded Polyline
public func encodeCoordinates(_ coordinates: [CLLocationCoordinate2D], precision: Double = 1e5) -> String {
    
    var previousCoordinate = IntegerCoordinates(0, 0)
    var encodedPolyline = ""
    
    for coordinate in coordinates {
        let intLatitude  = Int(round(coordinate.latitude * precision))
        let intLongitude = Int(round(coordinate.longitude * precision))
        
        let coordinatesDifference = (intLatitude - previousCoordinate.latitude, intLongitude - previousCoordinate.longitude)
        
        encodedPolyline += encodeCoordinate(coordinatesDifference)
        
        previousCoordinate = (intLatitude,intLongitude)
    }
    
    return encodedPolyline
}

/// This function encodes an `[CLLocation]` to a `String`
///
/// - parameter coordinates: The `Array` of `CLLocation` that you want to encode
/// - parameter precision: The precision used to encode locations (default: `1e5`)
///
/// - returns: A `String` representing the encoded Polyline
public func encodeLocations(_ locations: [CLLocation], precision: Double = 1e5) -> String {
    
    return encodeCoordinates(toCoordinates(locations), precision: precision)
}

/// This function encodes an `[UInt32]` to a `String`
///
/// - parameter levels: The `Array` of `UInt32` levels that you want to encode
///
/// - returns: A `String` representing the encoded Levels
public func encodeLevels(_ levels: [UInt32]) -> String {
    return levels.reduce("") {
        $0 + encodeLevel($1)
    }
}

class CoordinateContainer {
    let coordinates: [CLLocationCoordinate2D]
    
    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
    }
}

/// This function decodes a `String` to a `[CLLocationCoordinate2D]?`
///
/// - parameter encodedPolyline: `String` representing the encoded Polyline
/// - parameter precision: The precision used to decode coordinates (default: `1e5`)
///
/// - returns: A `[CLLocationCoordinate2D]` representing the decoded polyline if valid, `nil` otherwise
let locationCache = NSCache<NSString, CoordinateContainer>()
public func decodePolyline(_ encodedPolyline: String, precision: Double = 1e5) -> [CLLocationCoordinate2D]? {
    if let coords = locationCache.object(forKey: encodedPolyline as NSString) as? CoordinateContainer {
        return coords.coordinates
    }
        
    
    let data = encodedPolyline.data(using: String.Encoding.utf8)!
    
    let byteArray = (data as NSData).bytes.assumingMemoryBound(to: Int8.self)
    let length = Int(data.count)
    var position = Int(0)
    
    var decodedCoordinates = [CLLocationCoordinate2D]()
    
    var lat = 0.0
    var lon = 0.0
    
    while position < length {
      
        do {
            let resultingLat = try decodeSingleCoordinate(byteArray: byteArray, length: length, position: &position, precision: precision)
            lat += resultingLat
            
            let resultingLon = try decodeSingleCoordinate(byteArray: byteArray, length: length, position: &position, precision: precision)
            lon += resultingLon
        } catch {
            return nil
        }

        decodedCoordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    locationCache.setObject(CoordinateContainer(coordinates: decodedCoordinates), forKey: encodedPolyline as NSString)
    return decodedCoordinates
}

public func encodeTimestampAndAccuracy(timestampAndAccuracy: [TimeAndAccuracy]) -> String {
    if timestampAndAccuracy.count == 0 {
        return ""
    }
    
    return encodeCoordinates(timestampAndAccuracy.map(convertToCoordinate), precision: 1e5)
}

public func decodeTimestampAndAccuracy(encodedString: String) -> [TimeAndAccuracy]? {
    if encodedString == "" {
        return []
    }
    var fakeCoordinates: [CLLocationCoordinate2D]! = decodePolyline(encodedString, precision: 1e5)
    if fakeCoordinates == nil {
        return nil
    }
    return fakeCoordinates.map(convertFromCoordinate)
}


/// This function decodes a String to a [CLLocation]?
///
/// - parameter encodedPolyline: String representing the encoded Polyline
/// - parameter precision: The precision used to decode locations (default: 1e5)
///
/// - returns: A [CLLocation] representing the decoded polyline if valid, nil otherwise
public func decodePolyline(_ encodedPolyline: String, precision: Double = 1e5) -> [CLLocation]? {
    
    return decodePolyline(encodedPolyline, precision: precision).map(toLocations)
}

/// This function decodes a `String` to an `[UInt32]`
///
/// - parameter encodedLevels: The `String` representing the levels to decode
///
/// - returns: A `[UInt32]` representing the decoded Levels if the `String` is valid, `nil` otherwise
public func decodeLevels(_ encodedLevels: String) -> [UInt32]? {
    var remainingLevels = encodedLevels.unicodeScalars
    var decodedLevels   = [UInt32]()
    
    while remainingLevels.count > 0 {
        
        do {
            let chunk = try extractNextChunk(&remainingLevels)
            let level = decodeLevel(chunk)
            decodedLevels.append(level)
        } catch {
            return nil
        }
    }
    
    return decodedLevels
}


// MARK: - Private -

// MARK: Encode Coordinate

private func encodeCoordinate(_ locationCoordinate: IntegerCoordinates) -> String {
    
    let latitudeString  = encodeSingleComponent(locationCoordinate.latitude)
    let longitudeString = encodeSingleComponent(locationCoordinate.longitude)
    
    return latitudeString + longitudeString
}

private func encodeSingleComponent(_ value: Int) -> String {
    
    var intValue = value
    
    if intValue < 0 {
        intValue = intValue << 1
        intValue = ~intValue
    } else {
        intValue = intValue << 1
    }
    
    return encodeFiveBitComponents(intValue)
}

// MARK: Encode Levels

private func encodeLevel(_ level: UInt32) -> String {
    return encodeFiveBitComponents(Int(level))
}

private func encodeFiveBitComponents(_ value: Int) -> String {
    var remainingComponents = value
    
    var fiveBitComponent = 0
    var returnString = String()
    
    repeat {
        fiveBitComponent = remainingComponents & 0x1F
        
        if remainingComponents >= 0x20 {
            fiveBitComponent |= 0x20
        }
        
        fiveBitComponent += 63

        let char = UnicodeScalar(fiveBitComponent)!
        returnString.append(String(char))
        remainingComponents = remainingComponents >> 5
    } while (remainingComponents != 0)
    
    return returnString
}

// MARK: Decode Coordinate

// We use a byte array (UnsafePointer<Int8>) here for performance reasons. Check with swift 2 if we can
// go back to using [Int8]
private func decodeSingleCoordinate(byteArray: UnsafePointer<Int8>, length: Int, position: inout Int, precision: Double = 1e5) throws -> Double {
    
    guard position < length else { throw PolylineError.singleCoordinateDecodingError }
    
    let bitMask = Int8(0x1F)
    
    var coordinate: Int32 = 0
    
    var currentChar: Int8
    var componentCounter: Int32 = 0
    var component: Int32 = 0
    
    repeat {
        currentChar = byteArray[position] - 63
        component = Int32(currentChar & bitMask)
        coordinate |= (component << (5*componentCounter))
        position += 1
        componentCounter += 1
    } while ((currentChar & 0x20) == 0x20) && (position < length) && (componentCounter < 6)
    
    if (componentCounter == 6) && ((currentChar & 0x20) == 0x20) {
        throw PolylineError.singleCoordinateDecodingError
    }
    
    if (coordinate & 0x01) == 0x01 {
        coordinate = ~(coordinate >> 1)
    } else {
        coordinate = coordinate >> 1
    }
    
    return Double(coordinate) / precision
}

// MARK: Decode Levels

private func extractNextChunk(_ encodedString: inout String.UnicodeScalarView) throws -> String {
    var currentIndex = encodedString.startIndex
    
    while currentIndex != encodedString.endIndex {
        let currentCharacterValue = Int32(encodedString[currentIndex].value)
        if isSeparator(currentCharacterValue) {
            let extractedScalars = encodedString[encodedString.startIndex...currentIndex]
            encodedString = encodedString[encodedString.index(after: currentIndex)..<encodedString.endIndex]
            
            return String(extractedScalars)
        }
        
        currentIndex = encodedString.index(after: currentIndex)
    }
    
    throw PolylineError.chunkExtractingError
}

private func decodeLevel(_ encodedLevel: String) -> UInt32 {
    let scalarArray = [] + encodedLevel.unicodeScalars
    
    return UInt32(agregateScalarArray(scalarArray))
}

private func agregateScalarArray(_ scalars: [UnicodeScalar]) -> Int32 {
    let lastValue = Int32(scalars.last!.value)
    
    let fiveBitComponents: [Int32] = scalars.map { scalar in
        let value = Int32(scalar.value)
        if value != lastValue {
            return (value - 63) ^ 0x20
        } else {
            return value - 63
        }
    }
    
    return Array(fiveBitComponents.reversed()).reduce(0) { ($0 << 5 ) | $1 }
}

// MARK: Utilities

enum PolylineError: Error {
    case singleCoordinateDecodingError
    case chunkExtractingError
}

private func toCoordinates(_ locations: [CLLocation]) -> [CLLocationCoordinate2D] {
    return locations.map {location in location.coordinate}
}

private func toLocations(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocation] {
    return coordinates.map { coordinate in
        CLLocation(latitude:coordinate.latitude, longitude:coordinate.longitude)
    }
}

private func isSeparator(_ value: Int32) -> Bool {
    return (value - 63) & 0x20 != 0x20
}

private typealias IntegerCoordinates = (latitude: Int, longitude: Int)
public typealias TimeAndAccuracy = (timestamp: Date, accuracy: Double)

private func convertToCoordinate(timeAndAcc: TimeAndAccuracy) -> CLLocationCoordinate2D {
    var accuracy = timeAndAcc.accuracy > 4095 ? 4095 : timeAndAcc.accuracy
    let timestamp = timeAndAcc.timestamp.timeIntervalSince1970
    
    assert(accuracy >= 0 && timestamp >= 0, "Need positive values to encode")
    
    var ux = unsafeBitCast(UInt32(timestamp), to: UInt32.self)
    var uy = unsafeBitCast(UInt32(accuracy), to: UInt32.self)

    var twoTo22 = UInt32(pow(2.0, 22.0))
    var bottom = (ux & (twoTo22 - 1))
    var top = (ux  >> 22)
    
    top = (top << 12) | uy
    
    var lat = Double(bottom) / 100000.0
    var lng = Double(top) / 100000.0
    
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

private func convertFromCoordinate(coord: CLLocationCoordinate2D) -> TimeAndAccuracy {
    var bottom = UInt32(round(coord.latitude * 100000.0))
    var top = UInt32(round(coord.longitude * 100000.0))
    
    var accuracy = UInt32(top & 0xFFF)
    var timestamp = (((top & ~accuracy) >> 12) << 22) | bottom
    
    return (timestamp: Date(timeIntervalSince1970: Double(timestamp)), accuracy: Double(accuracy))
}

class LocationContainer {
    var locations: [CLLocation]
    init(locations: [CLLocation]) {
        self.locations = locations
    }
}

@objc class PolylineUtils: NSObject {
    class func unsafeConvertPolylineStringsToPoints(encodedPolyline: String, encodedTimestampAndAccuracy: String) throws -> [CLLocation] {
        let poly = try Polyline(encodedPolyline: encodedPolyline, encodedTimestampAndAccuracy: encodedTimestampAndAccuracy)
        return poly.locations ?? []
    }
    
    class func convertPolylineStringsToPoints(encodedPolyline: String, encodedTimestampAndAccuracy: String)  -> [CLLocation] {
        do {
            let poly = try Polyline(encodedPolyline: encodedPolyline, encodedTimestampAndAccuracy: encodedTimestampAndAccuracy)
            return poly.locations ?? []
        } catch {
            return []
        }
    }
}
