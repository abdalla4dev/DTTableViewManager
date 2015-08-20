//
//  TableViewCellFactory.swift
//  DTTableViewManager
//
//  Created by Denys Telezhkin on 13.07.15.
//  Copyright (c) 2015 Denys Telezhkin. All rights reserved.
//

import UIKit
import Foundation
import ModelStorage

class TableViewFactory
{
    private let tableView: UITableView
    
    private var mappings = [ViewModelMapping]()
    
    var bundle = NSBundle.mainBundle()
    
    init(tableView: UITableView)
    {
        self.tableView = tableView
    }
    
    private func mappingForViewType(type: ViewType,modelTypeMirror: _MirrorType) -> ViewModelMapping?
    {
        var adjustedModelTypeMirror = RuntimeHelper.classClusterReflectionFromMirrorType(modelTypeMirror)
        return self.mappings.filter({ (mapping) -> Bool in
            return mapping.viewType == type && mapping.modelTypeMirror.summary == adjustedModelTypeMirror.summary
        }).first
    }
    
    private func addMappingForViewType<T:ModelTransfer>(type: ViewType, viewClass : T.Type)
    {
        if self.mappingForViewType(type, modelTypeMirror: _reflect(T.CellModel.self)) == nil
        {
            self.mappings.append(ViewModelMapping(viewType : type,
                viewTypeMirror : _reflect(T),
                modelTypeMirror: _reflect(T.CellModel.self),
                updateBlock: { (view, model) in
                    (view as! T).updateWithModel(model as! T.CellModel)
            }))
        }
    }
    
    func registerCellClass<T:ModelTransfer where T: UITableViewCell>(cellType : T.Type)
    {
        let reuseIdentifier = RuntimeHelper.classNameFromReflection(_reflect(cellType))
        if self.tableView.dequeueReusableCellWithIdentifier(reuseIdentifier) == nil
        {
            // Storyboard prototype cell
            self.tableView.registerClass(T.self, forCellReuseIdentifier: reuseIdentifier)
            
            if UINib.nibExistsWithNibName(reuseIdentifier, inBundle: bundle) {
                self.registerNibNamed(reuseIdentifier, forCellType: T.self)
            }
        }
        self.addMappingForViewType(.Cell, viewClass: T.self)
    }
    
    func registerNibNamed<T:ModelTransfer where T: UITableViewCell>(nibName : String, forCellType cellType: T.Type)
    {
        assert(UINib.nibExistsWithNibName(nibName, inBundle: bundle), "Register cell nib method should be called only if nib exists")
        
        let nib = UINib(nibName: nibName, bundle: bundle)
        let reuseIdentifier = RuntimeHelper.classNameFromReflection(_reflect(cellType))
        self.tableView.registerNib(nib, forCellReuseIdentifier: reuseIdentifier)
        self.addMappingForViewType(.Cell, viewClass: T.self)
    }
    
    func registerHeaderClass<T:ModelTransfer where T: UIView>(headerType : T.Type)
    {
        self.registerNibNamed(RuntimeHelper.classNameFromReflection(_reflect(headerType)), forHeaderType: headerType)
    }
    
    func registerFooterClass<T:ModelTransfer where T:UIView>(footerType: T.Type)
    {
        self.registerNibNamed(RuntimeHelper.classNameFromReflection(_reflect(footerType)), forFooterType: footerType)
    }
    
    func registerNibNamed<T:ModelTransfer where T:UIView>(nibName: String, forHeaderType headerType: T.Type)
    {
        assert(UINib.nibExistsWithNibName(nibName, inBundle: bundle), "Register header nib method should be called only if nib exists")
        let reuseIdentifier = RuntimeHelper.classNameFromReflection(_reflect(headerType))
        
        if T.isSubclassOfClass(UITableViewHeaderFooterView.self) {
            self.tableView.registerNib(UINib(nibName: nibName, bundle: bundle), forHeaderFooterViewReuseIdentifier: reuseIdentifier)
        }
        self.addMappingForViewType(.Header, viewClass: T.self)
    }
    
    func registerNibNamed<T:ModelTransfer where T:UIView>(nibName: String, forFooterType footerType: T.Type)
    {
        assert(UINib.nibExistsWithNibName(nibName, inBundle: bundle), "Register footer nib method should be called only if nib exists")
        let reuseIdentifier = RuntimeHelper.classNameFromReflection(_reflect(footerType))
        
        if T.isSubclassOfClass(UITableViewHeaderFooterView.self) {
            self.tableView.registerNib(UINib(nibName: nibName, bundle: bundle), forHeaderFooterViewReuseIdentifier: reuseIdentifier)
        }
        self.addMappingForViewType(.Footer, viewClass: T.self)
    }
    
    func cellForModel(model: Any, atIndexPath indexPath:NSIndexPath) -> UITableViewCell
    {
        guard let unwrappedModel = RuntimeHelper.recursivelyUnwrapAnyValue(model) else {
            assertionFailure("Received nil model at indexPath: \(indexPath)")
            return UITableViewCell()
        }
        
        let typeMirror = RuntimeHelper.mirrorFromModel(unwrappedModel)
        if let mapping = self.mappingForViewType(.Cell, modelTypeMirror: typeMirror)
        {
            let cellClassName = RuntimeHelper.classNameFromReflection(mapping.viewTypeMirror)
            let cell = tableView.dequeueReusableCellWithIdentifier(cellClassName, forIndexPath: indexPath)
            mapping.updateBlock(cell, unwrappedModel)
            return cell
        }
        
        assertionFailure("Unable to find cell mappings for type: \(_reflect(typeMirror.valueType).summary)")
        
        return UITableViewCell()
    }
    
    func headerFooterViewWithMapping(mapping: ViewModelMapping, unwrappedModel: Any) -> UIView?
    {
        let viewClassName = RuntimeHelper.classNameFromReflection(mapping.viewTypeMirror)
        var view = self.tableView.dequeueReusableHeaderFooterViewWithIdentifier(viewClassName) as? UIView
        if view == nil {
            if let type = mapping.viewTypeMirror.value as? UIView.Type {
                view = type.dt_loadFromXibInBundle(bundle)
            }
        }
        precondition(view != nil,"failed creating view of type: \(viewClassName) for model: \(unwrappedModel)")
        
        mapping.updateBlock(view!,unwrappedModel)
        return view
    }
    
    private func headerFooterViewOfType(type: ViewType, model : Any) -> UIView?
    {
        let unwrappedModel = RuntimeHelper.recursivelyUnwrapAnyValue(model)
        if unwrappedModel == nil {
            assertionFailure("Received nil model for headerFooterViewModel")
        }
        
        let typeMirror = RuntimeHelper.mirrorFromModel(unwrappedModel!)
        
        if let mapping = self.mappingForViewType(type, modelTypeMirror: typeMirror) {
            return self.headerFooterViewWithMapping(mapping, unwrappedModel: unwrappedModel!)
        }
        
        return nil
    }
    
    func headerViewForModel(model: Any) -> UIView?
    {
        return self.headerFooterViewOfType(.Header, model: model)
    }
    
    func footerViewForModel(model: Any) -> UIView?
    {
        return self.headerFooterViewOfType(.Footer, model: model)
    }
}
