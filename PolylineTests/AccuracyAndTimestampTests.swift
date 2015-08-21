//
//  AccuracyAndTimestampTests.swift
//  Polyline
//
//  Created by ARUN VIJAYVERGIYA on 8/21/15.
//  Copyright (c) 2015 Raphael MOR. All rights reserved.
//

import UIKit
import XCTest
import CoreLocation
import Polyline

class AccuracyAndTimestampTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testEncodeDecodeAccuracies() {

        var pointShorthands : [(Double, Double, Double, Double)] = [
            (40.72372398063732, -73.95112139789549, 0, 65),
            (40.72372398063732, -73.95112139789549, 978307200, 65),
            (40.72359878173449, -73.95098797194744, 1432683587.495, 391.0113778630821),
            (40.68662238564845, -73.98253151847045, 1432684299.411, 1767.560647477974),
            (40.68673422947597, -73.99050771110113, 1432684355.162, 65),
            (40.68703909243902, -73.99111054403679, 1432684411.605, 65),
            (40.6874308109076, -73.99200380522169, 1432684467.417, 65),
            (40.687603352769, -73.99252671198215, 1432684523.067, 76.36571466773937),
            (40.687603352769, -73.99252671198215, 2147471999, 4000.0)
        ]
        
        var locationsToTest : [CLLocation] = pointShorthands.map {
            CLLocation(
                coordinate: CLLocationCoordinate2DMake($0.0, $0.1),
                altitude: 0,
                horizontalAccuracy: $0.3,
                verticalAccuracy: 0,
                course: 0,
                speed: 0,
                timestamp: NSDate(timeIntervalSince1970: $0.2)
            )
        }
        let sortedLocations = locationsToTest.sorted({ $0.timestamp.timeIntervalSince1970 < $1.timestamp.timeIntervalSince1970 })
        
        var polyline = Polyline(locations: sortedLocations)
        var encodedCoords: String! = polyline.encodedPolyline
        var encodedTimeAndAcc: String! = polyline.encodedTimestampAndAccuracy
        println(encodedCoords)
        println(encodedTimeAndAcc)
        
        XCTAssert(encodedCoords != nil && encodedTimeAndAcc != nil, "Bad Encoding")
        
        var decodedPolyline = Polyline(encodedPolyline: encodedCoords, encodedTimestampAndAccuracy: encodedTimeAndAcc)
        XCTAssert(decodedPolyline.coordinates?.count == sortedLocations.count &&
            decodedPolyline.timestampAndAccuracy?.count == sortedLocations.count,
            "decoding didn't work"
        )
        
        for (ii, loc) in enumerate(decodedPolyline.locations!) {
            var loc2 = sortedLocations[ii]
            
            XCTAssert(round(loc.coordinate.latitude * 1e5) == round(loc2.coordinate.latitude * 1e5), "Decoding does not produce same point")
            XCTAssert(round(loc.coordinate.longitude * 1e5) == round(loc2.coordinate.longitude * 1e5), "Decoding does not produce same point")
            XCTAssert(abs(loc.timestamp.timeIntervalSinceDate(loc2.timestamp)) < 1, "Decoding does not produce same point")
            XCTAssert(floor(loc.horizontalAccuracy) == floor(loc2.horizontalAccuracy), "Decoding does not produce same point")
        }
        
        
    }
}
