//
//  SpreadsheetLayout.swift
//  DoControl
//
//  Created by Wojtek Kordylewski on 15.03.16.
//  Copyright © 2016 indiControl GmbH. All rights reserved.
//

import UIKit

public protocol SpreadsheetLayoutDelegate: class {
    /**
        Asks the delegate for the row height in each section.
     
        - Parameter layout: The referenced SpreadsheetLayout.
        - Parameter section: The referenced section for which the height must be returned.
     
        - Returns: Height of the referenced section.
    */
    func spreadsheet(layout: SpreadsheetLayout, heightForRowsInSection section: Int) -> CGFloat
    
    /**
     Asks the delegate for the widths of the side rows in the layout.
     
     - Parameter layout: The referenced SpreadsheetLayout.
     
     - Returns: Tuple representing the left and the right row width of the spreadsheet layout. If you return `nil` for the tuple's element(s) the respective side row will not be drawn by the layout.
     */
    func widthsOfSideRowsInSpreadsheet(layout: SpreadsheetLayout) -> (left: CGFloat?, right: CGFloat?)
    
    /**
     Asks the delegate for the width of a column at a specific index.
     
     - Parameter layout: The referenced SpreadsheetLayout.
     - Parameter index: The index of the column.
     
     - Returns: Width of the column.
     */
    func spreadsheet(layout: SpreadsheetLayout, widthForColumnAtIndex index: Int) -> CGFloat
    
    /**
     Asks the delegate for the heights of the header and footer of the layout.
     
     - Parameter layout: The referenced SpreadsheetLayout.
     
     - Returns: Tuple representing the header and the footer height of the spreadsheet layout. If you return `nil` for the tuple's element(s) the respective header/footer will not be drawn by the layout.
     */
    func heightsOfHeaderAndFooterColumnsInSpreadsheet(layout: SpreadsheetLayout) -> (headerHeight: CGFloat?, footerHeight: CGFloat?)
    
    func customizeLayoutAttributes(_ attributes: SpreadsheetLayoutAttributes, for viewType: SpreadsheetLayout.ViewKindType)
}

extension UICollectionView {
    /// Reset the layout cache of your SpreadsheetLayout (if available) and reload the collection view.
    func reloadDataAndSpreadsheetLayout() {
        if let spreadsheetLayout = self.collectionViewLayout as? SpreadsheetLayout {
            spreadsheetLayout.resetLayoutCache()
        }
        self.reloadData()
    }
}

public class SpreadsheetLayoutAttributes: UICollectionViewLayoutAttributes {
    public var text: String?
    public var color: UIColor?
}

public class SpreadsheetLayout: UICollectionViewLayout {
    /// Delegate of Spreadsheetlayout
    public weak var delegate: SpreadsheetLayoutDelegate?
    
    /// Set to `true` if the the left row header shall remain sticky on screen (default `true`).
    public var stickyLeftRowHeader = true
    
    /// Set to `true` if the the right row header shall remain sticky on screen (default `true`).
    public var stickyRightRowHeader = true
    
    /// Set to `true` if the the top column header shall remain sticky on screen (default `true`).
    public var stickyTopColumnHeader = true
    
    /// Set to `true` if the the bottom column header shall remain sticky on screen (default `true`).
    public var stickyBottomColumnFooter = true
    
    fileprivate var cacheBuilt = false
    fileprivate lazy var cellCache = [[UICollectionViewLayoutAttributes]]()
    fileprivate lazy var leftRowCache = [UICollectionViewLayoutAttributes]()
    fileprivate lazy var rightRowCache = [UICollectionViewLayoutAttributes]()
    fileprivate lazy var topColumnCache = [UICollectionViewLayoutAttributes]()
    fileprivate lazy var bottomColumnCache = [UICollectionViewLayoutAttributes]()
    
    fileprivate var topLeftGapSpaceLayoutAttributes: UICollectionViewLayoutAttributes?
    fileprivate var topRightGapSpaceLayoutAttributes: UICollectionViewLayoutAttributes?
    fileprivate var bottomLeftGapSpaceLayoutAttributes: UICollectionViewLayoutAttributes?
    fileprivate var bottomRightGapSpaceLayoutAttributes: SpreadsheetLayoutAttributes?
    
    fileprivate var contentHeight: CGFloat = 0
    fileprivate var contentWidth: CGFloat = 0
    fileprivate var decorationViewSet = (topLeft: false, topRight: false, bottomLeft: false, bottomRight: false)

    /// Available ViewKindTypes for Decoration- and Supplementary Views
    public enum ViewKindType: String {
        case leftRowHeadline = "LeftRowHeadlineKind"
        case rightRowHeadline = "RightRowHeadlineKind"
        case topColumnHeader = "TopColumnHeaderKind"
        case bottomColumnFooter = "BottomColumnFooterKind"
        
        case decorationTopLeft = "DecorationTopLeftKind"
        case decorationTopRight = "DecorationTopRightKind"
        case decorationBottomLeft = "DecorationBottomLeftKind"
        case decorationBottomRight = "DecorationBottomRightKind"
    }
    
    /// Associative values of this enum represent `AnyClass` or `UINib`
    public enum DecorationViewType {
        case asClass(AnyClass)
        case asNib(UINib)
    }
    
    /// Convenience initializer. Pass delegate and the respective Decoration View types if required.
    public convenience init(delegate: SpreadsheetLayoutDelegate?, topLeftDecorationViewType: DecorationViewType? = nil, topRightDecorationViewType: DecorationViewType? = nil, bottomLeftDecorationViewType: DecorationViewType? = nil, bottomRightDecorationViewType: DecorationViewType? = nil) {
        self.init()
        self.delegate = delegate
        
        if let topLeftDeco = topLeftDecorationViewType {
            self.decorationViewSet.topLeft = true
            self.register(decorationViewType: topLeftDeco, decorationKind: ViewKindType.decorationTopLeft.rawValue)
        }
        
        if let topRightDeco = topRightDecorationViewType {
            self.decorationViewSet.topRight = true
            self.register(decorationViewType: topRightDeco, decorationKind: ViewKindType.decorationTopRight.rawValue)
        }
        
        if let bottomLeftDeco = bottomLeftDecorationViewType {
            self.decorationViewSet.bottomLeft = true
            self.register(decorationViewType: bottomLeftDeco, decorationKind: ViewKindType.decorationBottomLeft.rawValue)
        }
        
        if let bottomRightDeco = bottomRightDecorationViewType {
            self.decorationViewSet.bottomRight = true
            self.register(decorationViewType: bottomRightDeco, decorationKind: ViewKindType.decorationBottomRight.rawValue)
            
        }
    }
    
    private func register(decorationViewType: DecorationViewType, decorationKind: String) {
        switch decorationViewType {
        case .asClass(let cl):
            self.register(cl, forDecorationViewOfKind: decorationKind)
        case .asNib(let nb):
            self.register(nb, forDecorationViewOfKind: decorationKind)
        }
    }
    
    override public func prepare() {
        guard let cv = self.collectionView, let del = self.delegate, !self.cacheBuilt else { return }
        
        //BASIC Setup
        var maxItems = 0
        
        let widthTuple = del.widthsOfSideRowsInSpreadsheet(layout: self)
        let headerFooterTuple = del.heightsOfHeaderAndFooterColumnsInSpreadsheet(layout: self)
        
        let maxTopColumnHeight = headerFooterTuple.headerHeight ?? 0
        
        //Calculate left Row cache and heights for sections
        var rowHeights = [CGFloat]()
        var currentRowYoffset = maxTopColumnHeight
        for section in 0 ..< cv.numberOfSections {
            let rowHeight = del.spreadsheet(layout:self, heightForRowsInSection: section)
            rowHeights.append(rowHeight)
            
            let items = cv.numberOfItems(inSection: section)
            maxItems = max(maxItems, items)
            
            if let maxLeftRowWidth = widthTuple.left {
                let leftRowAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: ViewKindType.leftRowHeadline.rawValue, with: IndexPath(item: 0, section: section))
                leftRowAttributes.frame = CGRect(x: 0, y: currentRowYoffset, width: maxLeftRowWidth, height: rowHeight)
                self.leftRowCache.append(leftRowAttributes)
            }
            currentRowYoffset += rowHeight
        }
    
        var columnWidths = [CGFloat]()
        var currentColumnHeadlineXoffset = widthTuple.left ?? 0
        for item in 0 ..< maxItems {
            let topColumnWidth = del.spreadsheet(layout: self, widthForColumnAtIndex: item)
            columnWidths.append(topColumnWidth)
            
            if maxTopColumnHeight > 0 {
                let topColumnAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: ViewKindType.topColumnHeader.rawValue, with: IndexPath(item: item, section: 0))
                topColumnAttributes.frame = CGRect(x: currentColumnHeadlineXoffset, y: 0, width: topColumnWidth, height: maxTopColumnHeight)
                self.topColumnCache.append(topColumnAttributes)
                
                currentColumnHeadlineXoffset += topColumnWidth
            }
        }
        
        //Cell Data Setup
        
        var currentCellXoffset = widthTuple.left ?? 0
        var currentCellYoffset = maxTopColumnHeight
        for currentSection in 0 ..< rowHeights.count {
            let sectionHeight = rowHeights[currentSection]
            var sectionAttributes = [UICollectionViewLayoutAttributes]()
            currentCellXoffset = widthTuple.left ?? 0
            for currentItem in 0 ..< columnWidths.count {
                let rowWidth = columnWidths[currentItem]
                let cellAttributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: currentItem, section: currentSection))
                cellAttributes.frame = CGRect(x: currentCellXoffset, y: currentCellYoffset, width: rowWidth, height: sectionHeight)
                currentCellXoffset += rowWidth
                sectionAttributes.append(cellAttributes)
            }
            self.cellCache.append(sectionAttributes)
            currentCellYoffset += sectionHeight
        }
        
        let numberOfSections = cv.numberOfSections
        if numberOfSections > 0 {
            if let leftRowWidth = widthTuple.left {
                if self.decorationViewSet.topLeft && maxTopColumnHeight > 0 {
                    let topLeftAttributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: ViewKindType.decorationTopLeft.rawValue, with: IndexPath(item: 0, section: 0))
                    topLeftAttributes.frame = CGRect(x: 0, y: 0, width: leftRowWidth, height: maxTopColumnHeight)
                    self.topLeftGapSpaceLayoutAttributes = topLeftAttributes
                }
                
                if let bottomColumnHeight = headerFooterTuple.footerHeight , self.decorationViewSet.bottomLeft {
                    let bottomLeftAttributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: ViewKindType.decorationBottomLeft.rawValue, with: IndexPath(item: 0, section: numberOfSections - 1))
                    let yVal = self.stickyBottomColumnFooter ? min(cv.bounds.height - bottomColumnHeight, currentCellYoffset) : currentCellYoffset

                    bottomLeftAttributes.frame = CGRect(x: 0, y: yVal, width: leftRowWidth, height: bottomColumnHeight)
                    self.bottomLeftGapSpaceLayoutAttributes = bottomLeftAttributes
                }
            }
            
            if let rightRowWidth = widthTuple.right {
                if self.decorationViewSet.topRight && maxTopColumnHeight > 0 {
                    let topRightAttributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: ViewKindType.decorationTopRight.rawValue, with: IndexPath(item: cv.numberOfItems(inSection: 0) - 1, section: 0))
                    if self.stickyRightRowHeader {
                        topRightAttributes.frame = CGRect(x: min(cv.bounds.width - rightRowWidth, currentCellXoffset), y: 0, width: rightRowWidth, height: maxTopColumnHeight)
                    }
                    else {
                        topRightAttributes.frame = CGRect(x: currentCellXoffset, y: 0, width: rightRowWidth, height: maxTopColumnHeight)
                    }
                    self.topRightGapSpaceLayoutAttributes = topRightAttributes
                }
                
                if let bottomColumnHeight = headerFooterTuple.footerHeight , self.decorationViewSet.bottomRight {
                    let bottomRightAttributes = SpreadsheetLayoutAttributes(forDecorationViewOfKind: ViewKindType.decorationBottomRight.rawValue, with: IndexPath(item: 0, section: numberOfSections - 1))
                    
                    let xVal = self.stickyRightRowHeader ? min(cv.bounds.width - rightRowWidth, currentCellXoffset) : currentCellXoffset
                    let yVal = self.stickyBottomColumnFooter ? min(cv.bounds.height - bottomColumnHeight, currentCellYoffset) : currentCellYoffset
                    
                    bottomRightAttributes.frame = CGRect(x: xVal, y: yVal, width: rightRowWidth, height: bottomColumnHeight)
                    delegate?.customizeLayoutAttributes(bottomRightAttributes, for: .decorationBottomRight)
                    self.bottomRightGapSpaceLayoutAttributes = bottomRightAttributes
                }
                
                var currentRightRowOffsetY = maxTopColumnHeight
                for section in 0 ..< cv.numberOfSections {
                    let sectionHeight = rowHeights[section]
                    let rightRowAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: ViewKindType.rightRowHeadline.rawValue, with: IndexPath(item: cv.numberOfItems(inSection: 0) - 1, section: section))
                    if self.stickyRightRowHeader {
                        rightRowAttributes.frame = CGRect(x: min(cv.bounds.width - rightRowWidth, currentCellXoffset), y: currentRightRowOffsetY, width: rightRowWidth, height: sectionHeight)
                    }
                    else {
                        rightRowAttributes.frame = CGRect(x: currentCellXoffset, y: currentRightRowOffsetY, width: rightRowWidth, height: sectionHeight)
                    }
                    
                    self.rightRowCache.append(rightRowAttributes)
                    currentRightRowOffsetY += sectionHeight
                }
                currentCellXoffset += rightRowWidth
            }
            
            var currentBottomOffsetX = widthTuple.left ?? 0
            if let bottomColumnHeight = headerFooterTuple.footerHeight {
                for currentItem in 0 ..< columnWidths.count {
                    let rowWidth = columnWidths[currentItem]
                    let bottomColumnAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: ViewKindType.bottomColumnFooter.rawValue, with: IndexPath(item: currentItem, section: numberOfSections - 1))
                    
                    let yVal = self.stickyBottomColumnFooter ? max(0, min(cv.bounds.height - bottomColumnHeight, currentCellYoffset)) : currentCellYoffset

                    bottomColumnAttributes.frame = CGRect(x: currentBottomOffsetX, y: yVal, width: rowWidth, height: bottomColumnHeight)
                    self.bottomColumnCache.append(bottomColumnAttributes)
                    currentBottomOffsetX += rowWidth
                }
                currentCellYoffset += bottomColumnHeight
            }
        }
        
        if self.contentWidth != currentCellXoffset {
            cv.setContentOffset(CGPoint.zero, animated: false)
        }
        
        self.contentWidth = currentCellXoffset
        self.contentHeight = currentCellYoffset
        self.cacheBuilt = true
    }
    
    override public var collectionViewContentSize : CGSize {
        return CGSize(width: self.contentWidth, height: self.contentHeight)
    }
    
    override public func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let cv = self.collectionView else { return nil }
        
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        
        //CELLs
        for cellCacheArray in self.cellCache {
            for cellAttributes in cellCacheArray where cellAttributes.frame.intersects(rect) {
                cellAttributes.zIndex = 0
                layoutAttributes.append(cellAttributes)
            }
        }
        
        //LEFT ROW
        if self.stickyLeftRowHeader && cv.contentOffset.x >= 0 {
            let contentOffsetX = cv.contentOffset.x
            
            if contentOffsetX >= 0 {
                for rowAttributes in self.leftRowCache {
                    rowAttributes.frame.origin.x = contentOffsetX
                    rowAttributes.zIndex = 1000
                    layoutAttributes.append(rowAttributes)
                }
            }
        }
        else {
            for rowAttributes in self.leftRowCache where rowAttributes.frame.intersects(rect) {
                rowAttributes.frame.origin.x = 0
                rowAttributes.zIndex = 1000
                layoutAttributes.append(rowAttributes)
            }
        }
        
        //RIGHT ROW
        if let rightRowWidth = self.delegate?.widthsOfSideRowsInSpreadsheet(layout: self).right {
            if self.stickyRightRowHeader && cv.contentOffset.x <= self.contentWidth - cv.bounds.width {
                for rowAttributes in self.rightRowCache {
                    rowAttributes.frame.origin.x = cv.contentOffset.x + cv.bounds.width - rightRowWidth
                    rowAttributes.zIndex = 1000
                    layoutAttributes.append(rowAttributes)
                }
            }
            else {
                for rowAttributes in self.rightRowCache where rowAttributes.frame.intersects(rect) {
                    rowAttributes.frame.origin.x = self.contentWidth - rightRowWidth
                    rowAttributes.zIndex = 1000
                    layoutAttributes.append(rowAttributes)
                }
            }
        }
        
        //TOP COLUMN
        if self.stickyTopColumnHeader && cv.contentOffset.y >= 0 {
            for columnAttributes in self.topColumnCache {
                columnAttributes.frame.origin.y = cv.contentOffset.y
                columnAttributes.zIndex = 2000
                layoutAttributes.append(columnAttributes)
            }
        }
        else {
            for columnAttributes in self.topColumnCache where columnAttributes.frame.intersects(rect) {
                columnAttributes.frame.origin.y = 0
                columnAttributes.zIndex = 2000
                layoutAttributes.append(columnAttributes)
            }
        }
        
        //BOTTOM COLUMN
        
        if let bottomColumnHeight = self.delegate?.heightsOfHeaderAndFooterColumnsInSpreadsheet(layout: self).footerHeight {
            if self.stickyBottomColumnFooter && cv.contentOffset.y <= self.contentHeight - cv.bounds.height {
                for columnAttributes in self.bottomColumnCache {
                    columnAttributes.frame.origin.y = cv.contentOffset.y + cv.bounds.height - bottomColumnHeight
                    columnAttributes.zIndex = 2000
                    layoutAttributes.append(columnAttributes)
                }
            }
            else {
                for columnAttributes in self.bottomColumnCache  {
                    if columnAttributes.frame.intersects(rect) {
                        columnAttributes.frame.origin.y = self.contentHeight - bottomColumnHeight
                        columnAttributes.zIndex = 2000
                        layoutAttributes.append(columnAttributes)
                    }
                }
            }
        }
        
        //TOP LEFT GAP SPACE
        if let topLeftGapSpaceAttributes = self.topLeftGapSpaceLayoutAttributes {
            if self.stickyLeftRowHeader && cv.contentOffset.x >= 0 {
                topLeftGapSpaceAttributes.frame.origin.x = cv.contentOffset.x
            }
            else if topLeftGapSpaceAttributes.frame.intersects(rect) {
                topLeftGapSpaceAttributes.frame.origin.x = 0
            }
            
            if self.stickyTopColumnHeader && cv.contentOffset.y >= 0 {
                topLeftGapSpaceAttributes.frame.origin.y = cv.contentOffset.y
            }
            else if topLeftGapSpaceAttributes.frame.intersects(rect) {
                topLeftGapSpaceAttributes.frame.origin.y = 0
            }
            
            topLeftGapSpaceAttributes.zIndex = 3000
            layoutAttributes.append(topLeftGapSpaceAttributes)
        }
        
        //BOTTOM LEFT GAP SPACE
        if let bottomLeftGapSpaceAttributes = self.bottomLeftGapSpaceLayoutAttributes {
            if self.stickyLeftRowHeader && cv.contentOffset.x >= 0 {
                bottomLeftGapSpaceAttributes.frame.origin.x = cv.contentOffset.x
            }
            else if bottomLeftGapSpaceAttributes.frame.intersects(rect) {
                bottomLeftGapSpaceAttributes.frame.origin.x = 0
            }
            
            if self.stickyBottomColumnFooter && cv.contentOffset.y <= self.contentHeight - cv.bounds.height {
                bottomLeftGapSpaceAttributes.frame.origin.y = cv.contentOffset.y + cv.bounds.height - bottomLeftGapSpaceAttributes.frame.height
            }
            else {
                bottomLeftGapSpaceAttributes.frame.origin.y = self.contentHeight - bottomLeftGapSpaceAttributes.frame.height
            }
            
            bottomLeftGapSpaceAttributes.zIndex = 3000
            layoutAttributes.append(bottomLeftGapSpaceAttributes)
        }
        
        //TOP RIGHT GAP SPACE
        if let topRightGapSpaceAttributes = self.topRightGapSpaceLayoutAttributes {
            if self.stickyRightRowHeader && cv.contentOffset.x <= self.contentWidth - cv.bounds.width {
                topRightGapSpaceAttributes.frame.origin.x = cv.contentOffset.x + cv.bounds.width - topRightGapSpaceAttributes.frame.width
            }
            else if topRightGapSpaceAttributes.frame.intersects(rect) {
                topRightGapSpaceAttributes.frame.origin.x = self.contentWidth - topRightGapSpaceAttributes.frame.width
            }
            
            if self.stickyTopColumnHeader && cv.contentOffset.y >= 0 {
                topRightGapSpaceAttributes.frame.origin.y = cv.contentOffset.y
            }
            else if topRightGapSpaceAttributes.frame.intersects(rect) {
                topRightGapSpaceAttributes.frame.origin.y = 0
            }
            
            topRightGapSpaceAttributes.zIndex = 3000
            layoutAttributes.append(topRightGapSpaceAttributes)
        }
        
        //BOTOM RIGHT GAP SPACE
        
        if let bottomRightGapSpaceAttributes = self.bottomRightGapSpaceLayoutAttributes {
            if self.stickyRightRowHeader && cv.contentOffset.x <= self.contentWidth - cv.bounds.width {
                bottomRightGapSpaceAttributes.frame.origin.x = cv.contentOffset.x + cv.bounds.width - bottomRightGapSpaceAttributes.frame.width
            }
            else if bottomRightGapSpaceAttributes.frame.intersects(rect) {
                bottomRightGapSpaceAttributes.frame.origin.x = self.contentWidth - bottomRightGapSpaceAttributes.frame.width
            }
            
            if self.stickyBottomColumnFooter && cv.contentOffset.y <= self.contentHeight - cv.bounds.height {
                bottomRightGapSpaceAttributes.frame.origin.y = cv.contentOffset.y + cv.bounds.height - bottomRightGapSpaceAttributes.frame.height
            }
            else {
                bottomRightGapSpaceAttributes.frame.origin.y = self.contentHeight - bottomRightGapSpaceAttributes.frame.height
            }
            
            bottomRightGapSpaceAttributes.zIndex = 3000
            layoutAttributes.append(bottomRightGapSpaceAttributes)
        }
        
        return layoutAttributes
    }
    
    override public func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return self.cellCache[indexPath.section][indexPath.row]
    }
    
    override public func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let viewKind = ViewKindType(rawValue: elementKind) else { fatalError("Invalid View Kind for string: \(elementKind)") }
        
        switch viewKind {
        case .leftRowHeadline:
            return self.leftRowCache[indexPath.section]
        case .rightRowHeadline:
            return self.rightRowCache[indexPath.section]
        case .topColumnHeader:
            return self.topColumnCache[indexPath.item]
        case .bottomColumnFooter:
            return self.bottomColumnCache[indexPath.item]
        case .decorationTopLeft, .decorationTopRight, .decorationBottomLeft, .decorationBottomRight:
            return nil
        }
    }
    
    override public func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let viewKind = ViewKindType(rawValue: elementKind) else { fatalError("Invalid View Kind for string: \(elementKind)") }

        switch viewKind {
        case .decorationTopLeft:
            return self.topLeftGapSpaceLayoutAttributes
        case .decorationTopRight:
            return self.topRightGapSpaceLayoutAttributes
        case .decorationBottomLeft:
            return self.bottomLeftGapSpaceLayoutAttributes
        case .decorationBottomRight:
            return self.bottomRightGapSpaceLayoutAttributes
        case .leftRowHeadline, .rightRowHeadline, .topColumnHeader, .bottomColumnFooter:
            return nil
        }
    }
    
    override public func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return self.stickyLeftRowHeader || self.stickyTopColumnHeader || self.stickyRightRowHeader || self.stickyBottomColumnFooter
    }
    
    /// Reset layout cache. This will cause the layout to recalculate all its display information.
    public func resetLayoutCache() {
        self.cellCache = []
        self.leftRowCache = []
        self.rightRowCache = []
        self.topColumnCache = []
        self.bottomColumnCache = []
        self.topLeftGapSpaceLayoutAttributes = nil
        self.topRightGapSpaceLayoutAttributes = nil
        self.bottomLeftGapSpaceLayoutAttributes = nil
        self.bottomRightGapSpaceLayoutAttributes = nil
        self.cacheBuilt = false
    }
}
